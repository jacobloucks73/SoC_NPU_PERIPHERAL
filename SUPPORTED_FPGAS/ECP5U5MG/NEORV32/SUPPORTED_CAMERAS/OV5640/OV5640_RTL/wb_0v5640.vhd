Library ieee;
Use ieee.std_logic_1164.All;
Use ieee.numeric_std.All;

Library work;

Use work.ov5640_image_buffer.All;

Entity wb_ov5640 Is
	Generic (
		BASE_ADDRESS                    : Std_ulogic_vector(31 Downto 0) := x"90010000"; --peripheral base (informational)
		CAMERA_CONTROL_ADDRESS          : Std_ulogic_vector(31 Downto 0) := x"90010000"; --Camera control register. [0] = 1 from master, capture image. Peripheral sets it to 0 after capturing an image
		CAMERA_STATUS_ADDRESS           : Std_ulogic_vector(31 Downto 0) := x"90010004"; --Camera status register. [0] = 1 = busy, [1] = 1 = done
		IMAGE_FORMAT_ADDRESS            : Std_ulogic_vector(31 Downto 0) := x"90010008"; --Image format. [0] = 1 for YUV422. (Lowest3 bits can be used to select the format) (not used)
		IMAGE_RESOLUTION_ADDRESS        : Std_ulogic_vector(31 Downto 0) := x"9001000C"; --[15:0] = image width. [31:16] = image height
		MASTER_WORDS_TO_READ_ADDRESS    : Std_ulogic_vector(31 Downto 0) := x"90010010"; --32-bit words the master has to read to gather the complete image
		SCCB_PROGRAM_STATUS_REG_ADDRESS : Std_ulogic_vector(31 Downto 0) := x"90010014"; --Register to show SCCB programmer status. [0] = start latched. [1] = program started. [2] = wrapper busy. [3] = done. [4] = error 
		IMAGE_BUFFER_BASE               : Std_ulogic_vector(31 Downto 0) := x"90011000"; --Image buffer base address
		SYSTEM_CLK_HZ                   : Integer                        := 72_000_000 --System clock frequency in Hz for timing calculations
	);
	Port (
		clk          : In    Std_ulogic; --system clock
		reset        : In    Std_ulogic; --synchronous reset
		i_wb_cyc     : In    Std_ulogic; --Wishbone: cycle valid
		i_wb_stb     : In    Std_ulogic; --Wishbone: strobe
		i_wb_we      : In    Std_ulogic; --Wishbone: 1=write, 0=read
		i_wb_addr    : In    Std_ulogic_vector(31 Downto 0);--Wishbone: address
		i_wb_data    : In    Std_ulogic_vector(31 Downto 0);--Wishbone: write data
		o_wb_ack     : Out   Std_ulogic; --Wishbone: acknowledge
		o_wb_stall   : Out   Std_ulogic; --Wishbone: stall (always '0')
		o_wb_data    : Out   Std_ulogic_vector(31 Downto 0); --Wishbone: read data
		--Interface for the camera harware
		SIO_C        : Inout Std_ulogic; --SIO_C - SCCB clock signal. FPGA -> Camera
		SIO_D        : Inout Std_ulogic; --SIO_D - SCCB data signal (bi-direcctional). FPGA <--> Camera
		VSYNC        : In    Std_ulogic; --Camera VSYNC signal
		HREF         : In    Std_ulogic; --Camera HREF signal
		PCLK         : In    Std_ulogic; --Camera PCLK signal
		Data         : In    Std_ulogic_vector (7 Downto 0); --Camera data out pins
		OV5640_RESET : Out   Std_ulogic; --Camera reset (active low)
		POWER_DOWN   : Out   Std_ulogic --Camera power down (active high)

	);
End Entity;

--2-wire SCCB is similar to I2C apparently. SIO_C = SCL and SIO_D = SDA
Architecture rtl Of wb_ov5640 Is
	--SCCB controller component
	Component sccb_i2c_wrapper Is
		Generic (
			INPUT_CLK_HZ : Integer := 72_000_000;
			BUS_CLK_HZ   : Integer := 400_000
		);
		Port (
			clk   : In    Std_ulogic;
			reset : In    Std_ulogic;
			--SCCB pins
			SIO_C : Inout Std_ulogic;
			SIO_D : Inout Std_ulogic;
			--control
			start : In    Std_ulogic; --1 to start
			busy  : Out   Std_ulogic; --0 = idle. 1 = busy
			done  : Out   Std_ulogic; --0 = not done. 1 = busy
			err   : Out   Std_ulogic --Included because the I2C controller has it	
		);
	End Component;
	--Power-up sequence for OV5640:
	--Initially, Reset (RST) is low and Power Down (PWDN) is high
	--Wait 5ms -> PWDN low
	--Wait 1ms -> RST high
	--Wait 50ms, then start SCCB programming

	Type powerup_state_t Is (
		PU_INIT, --Initially, Reset (RST) is low and Power Down (PWDN) is high
		PU_WAIT_5MS, --Wait 5ms before pulling PWDN low
		PU_PWDN_LOW, --PWDN pulled low
		PU_WAIT_1MS, --Wait 1ms before pulling Reset high
		PU_RESET_HIGH, --RST pulled high
		PU_WAIT_50MS, --Wait 50ms before SCCB programming
		PU_READY --Ready for SCCB programming
	);

	Signal powerup_state : powerup_state_t := PU_INIT;

	--Timing constants (clock cycles for each delay)
	Constant CYCLES_5MS : Integer := (SYSTEM_CLK_HZ / 1000) * 5; --5ms delay
	Constant CYCLES_1MS : Integer := (SYSTEM_CLK_HZ / 1000) * 1; --1ms delay
	Constant CYCLES_50MS : Integer := (SYSTEM_CLK_HZ / 1000) * 50; --50ms delay

	--Delay counter for power-up timing
	Signal powerup_delay_counter : Integer Range 0 To CYCLES_50MS := 0;

	--Flag to indicate camera hardware is ready for SCCB programming
	Signal camera_hw_ready : Std_ulogic := '0';

	--Main registers
	Signal camera_control_reg : Std_ulogic_vector(31 Downto 0) := (Others => '0');
	Signal camera_status_reg : Std_ulogic_vector(31 Downto 0) := (Others => '0');
	Signal image_format_reg : Std_ulogic_vector(31 Downto 0) := (Others => '0');
	Signal image_resolution_reg : Std_ulogic_vector(31 Downto 0) := (Others => '0');
	Signal master_words_to_read_reg : Std_ulogic_vector(31 Downto 0) := (Others => '0');
	Signal sccb_program_status_reg : Std_ulogic_vector(31 Downto 0) := (Others => '0');

	--Image buffer
	Signal image_buffer : tensor_mem_type := (Others => (Others => '0'));
	Signal image_buffer_wb_rdata : Std_ulogic_vector(31 Downto 0) := (Others => '0');

	--BRAM inference hints
	Attribute ram_style : String;
	Attribute syn_ramstyle : String;
	Attribute ram_style Of image_buffer : Signal Is "block";
	Attribute syn_ramstyle Of image_buffer : Signal Is "block_ram";

	--Registers to signal when data from camera can be written to the BRAM (and what data can be written). PCLK domain
	Signal cam_to_buffer_write_signal : Std_ulogic := '0'; --Signal from camera FSM to write to buffer
	Signal cam_to_buffer_index : unsigned(31 Downto 0) := (Others => '0'); --word index into the image buffer
	Signal cam_to_buffer_data : Std_ulogic_vector(31 Downto 0) := (Others => '0'); --Data to write at index 

	--Camera interface registers
	--SCCB controller
	Signal start_lat : Std_ulogic := '0';
	Signal busy_lat : Std_ulogic;
	Signal done_lat : Std_ulogic;
	Signal err_lat : Std_ulogic;
	Signal sccb_boot_program_started : Std_ulogic := '0';
	--Other latches
	Signal vsync_lat : Std_ulogic;
	Signal href_lat : Std_ulogic;
	Signal data_lat : Std_ulogic_vector (7 Downto 0) := (Others => '0');

	--Debug signals to record what stage of the image capture FSM we are in
	Signal cap_state_dbg_pclk : Std_ulogic_vector(2 Downto 0) := (Others => '0');
	Signal cap_state_dbg_c1 : Std_ulogic_vector(2 Downto 0) := (Others => '0');
	Signal cap_state_dbg_c2 : Std_ulogic_vector(2 Downto 0) := (Others => '0');

	--Debug signals to record whether we saw cap_req_ff2 high
	Signal cap_req_seen_pclk : Std_ulogic := '0';
	Signal cap_req_seen_c1 : Std_ulogic := '0';
	Signal cap_req_seen_c2 : Std_ulogic := '0';

	--Debug signals to record whether we saw VSYNC high
	Signal saw_vsync_high_pclk : Std_ulogic := '0';
	Signal saw_vsync_high_c1 : Std_ulogic := '0';
	Signal saw_vsync_high_c2 : Std_ulogic := '0';

	--Debug signals to record whether we saw VSYNC edge
	Signal saw_vsync_edge_pclk : Std_ulogic := '0';
	Signal saw_vsync_edge_c1 : Std_ulogic := '0';
	Signal saw_vsync_edge_c2 : Std_ulogic := '0';

	--Debug signals to record whether we saw HREF edge
	Signal saw_href_edge_pclk : Std_ulogic := '0';
	Signal saw_href_edge_c1 : Std_ulogic := '0';
	Signal saw_href_edge_c2 : Std_ulogic := '0';

	--Debug signals to record whether we saw PCLK edge
	Signal pclk_sync_1 : Std_ulogic := '0';
	Signal pclk_sync_2 : Std_ulogic := '0';
	Signal saw_pclk_edge_clk : Std_ulogic := '0';

	--Capture (PCLK domain)
	Type cap_state_t Is (CAP_IDLE, CAP_ARM, CAP_WAIT_ACTIVE, CAP_CAPTURE, CAP_DONE);
	Signal cap_state : cap_state_t := CAP_IDLE;

	Signal cap_busy_pclk : Std_ulogic := '0';
	Signal cap_done_pclk : Std_ulogic := '0';

	--sync capture request into PCLK domain
	--Two stage synchoronizers are required to avoid metastability problems as we are operating with two different clock domains. 
	--The camera_control_register (0) is a flip-plop with timing windows around the system clock. Reading it near PCLK's edge may give unknown values
	--We first read the camera_control_register (0) and then store it in ff1. It may be unstable, but by when we read ff1 to store in ff2, there should be enough time for the flip-flop to be stable to store correct values in ff2.
	Signal cap_req_ff1 : Std_ulogic := '0';
	Signal cap_req_ff2 : Std_ulogic := '0';

	--Edge detection for start request
	Signal cap_req_prev_pclk : Std_ulogic := '0';
	Signal cap_start_pulse : Std_ulogic := '0';
	--sync busy/done back into clk domain
	--Similar synchronizer logic as the cap_req registers
	Signal cap_busy_c1 : Std_ulogic := '0';
	Signal cap_busy_c2 : Std_ulogic := '0';
	Signal cap_done_c1 : Std_ulogic := '0';
	Signal cap_done_c2 : Std_ulogic := '0';
	Signal vsync_prev : Std_ulogic := '0';

	--YUV422 byte phase and grayscale packing
	Signal yuv_phase : unsigned(1 Downto 0) := (Others => '0'); --0=Y0 1=U 2=Y1 3=V
	Signal y_word_buf : Std_ulogic_vector(31 Downto 0) := (Others => '0');
	Signal y_byte_idx : unsigned(1 Downto 0) := (Others => '0'); --0..3
	Signal y_word_index : unsigned(31 Downto 0) := (Others => '0');
	Signal y_pixel_count : unsigned(31 Downto 0) := (Others => '0');

	--total pixels to capture
	--Similar synchronizer logic as the cap_req registers
	Signal total_pixels_clk : unsigned(31 Downto 0) := to_unsigned(MAX_DIM * MAX_DIM, 32);
	Signal total_pix_p1 : unsigned(31 Downto 0) := (Others => '0');
	Signal total_pix_p2 : unsigned(31 Downto 0) := (Others => '0');
	--Wishbone
	Signal ack_r : Std_ulogic := '0';
	Signal wb_req : Std_ulogic := '0'; --Variable tp combine checks (Clock is high and the slave (NPU) is selected)

	--Only read from the buffer over wishbone when the camera is not busy
	Signal camera_busy : Std_ulogic := '0';

	--Wishbone read mux selector (latched for the transaction being acknowledged)
	--000: register readback
	--001: image buffer window
	Signal wb_rsel : Std_ulogic_vector(2 Downto 0) := (Others => '0'); --select signal for tensor mux
	Signal reg_rdata : Std_ulogic_vector(31 Downto 0) := (Others => '0');

	--Address helper: translate byte address to word offset within a tensor window
	Function get_tensor_offset(addr, base : Std_ulogic_vector(31 Downto 0)) Return Natural Is
		Variable offset : unsigned(31 Downto 0);
	Begin
		offset := unsigned(addr) - unsigned(base); --word + byte offset (relative position of element from base address)
		Return to_integer(shift_right(offset, 2)); --Right shift 2 removes they byte offset within a word. We are left with just the word index
	End Function;

Begin

	--Simple, non-stalling slave peripheral
	o_wb_stall <= '0';
	o_wb_ack <= ack_r;
	--Select the camera
	wb_req <= i_wb_cyc And i_wb_stb; --Clock is high and the slave (NPU) is selected
	camera_busy <= cap_busy_c2; --camera busy
	--Camera powerup sequence process
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If (reset = '1') Then
				--At the beginning, RST is low and PWDN is high
				OV5640_RESET <= '0'; --RST low
				POWER_DOWN <= '1'; --PWDN high
				powerup_state <= PU_INIT;
				powerup_delay_counter <= 0;
				camera_hw_ready <= '0';
			Else
				Case powerup_state Is

					When PU_INIT =>
						--Initial state: RST low, PWDN high
						OV5640_RESET <= '0';
						POWER_DOWN <= '1';
						powerup_delay_counter <= 0;
						camera_hw_ready <= '0';
						powerup_state <= PU_WAIT_5MS;
					When PU_WAIT_5MS =>
						--Wait 5ms
						OV5640_RESET <= '0';
						POWER_DOWN <= '1';
						camera_hw_ready <= '0';
						If (powerup_delay_counter < CYCLES_5MS - 1) Then
							powerup_delay_counter <= powerup_delay_counter + 1;
						Else
							powerup_delay_counter <= 0;
							powerup_state <= PU_PWDN_LOW;
						End If;
					When PU_PWDN_LOW =>
						--Pull PWDN low to wake up the camera
						OV5640_RESET <= '0';
						POWER_DOWN <= '0'; --PWDN low
						camera_hw_ready <= '0';
						powerup_delay_counter <= 0;
						powerup_state <= PU_WAIT_1MS;
					When PU_WAIT_1MS =>
						--Wait 1ms after PWDN goes low
						--OV5640_RESET <= '0';
						--POWER_DOWN <= '0';
						camera_hw_ready <= '0';
						If (powerup_delay_counter < CYCLES_1MS - 1) Then
							powerup_delay_counter <= powerup_delay_counter + 1;
						Else
							powerup_delay_counter <= 0;
							powerup_state <= PU_RESET_HIGH;
						End If;
					When PU_RESET_HIGH =>
						--Pull RST high
						OV5640_RESET <= '1'; --RST high
						POWER_DOWN <= '0';
						camera_hw_ready <= '0';
						powerup_delay_counter <= 0;
						powerup_state <= PU_WAIT_50MS;
					When PU_WAIT_50MS =>
						--Wait 50ms before starting SCCB initialization
						--OV5640_RESET <= '1';
						--POWER_DOWN <= '0';
						camera_hw_ready <= '0';
						If (powerup_delay_counter < CYCLES_50MS - 1) Then
							powerup_delay_counter <= powerup_delay_counter + 1;
						Else
							powerup_delay_counter <= 0;
							powerup_state <= PU_READY;
						End If;
					When PU_READY =>
						--Camera hardware is ready for SCCB programming
						OV5640_RESET <= '1';
						POWER_DOWN <= '0';
						camera_hw_ready <= '1';
						--Stay in this state
				End Case;
			End If;
		End If;
	End Process;

	--SCCB controller
	sccb_controller_inst : sccb_i2c_wrapper
	Port Map(
		clk   => clk,
		reset => reset,
		SIO_C => SIO_C,
		SIO_D => SIO_D,
		start => start_lat,
		busy  => busy_lat,
		done  => done_lat,
		err   => err_lat
	);

	--Start SCCB programming only when camera hardware is ready
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If (reset = '1') Then
				sccb_boot_program_started <= '0';
				start_lat <= '0';
			Else
				--Only start SCCB programming when camera hardware is ready
				If (sccb_boot_program_started = '0' And camera_hw_ready = '1') Then
					start_lat <= '1'; --request sccb wrapper to program the camera
					If (busy_lat = '1') Then --If wrapper is busy, then it has started
						start_lat <= '0'; --Deassert start latch input for wrapper
						sccb_boot_program_started <= '1'; --never request wrapper again
					End If;
				Else
					start_lat <= '0';
				End If;
			End If;
		End If;
	End Process;

	--Process to set bits of SCCB program status register. [0] = start latched. [1] = program started. [2] = wrapper busy. [3] = done. [4] = error
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If (reset = '1') Then
				sccb_program_status_reg <= (Others => '0');
			Else
				If (start_lat = '1') Then
					sccb_program_status_reg (0) <= '1';
				End If;
				If (sccb_boot_program_started = '1') Then
					sccb_program_status_reg (1) <= '1';
				End If;
				If (busy_lat = '1') Then
					sccb_program_status_reg (2) <= '1';
				End If;
				If (done_lat = '1') Then
					sccb_program_status_reg (3) <= '1';
				End If;
				If (err_lat = '1') Then
					sccb_program_status_reg (4) <= '1';
				End If;
			End If;
		End If;
	End Process;

	--Sync start request + total_pixels into PCLK domain
	Process (PCLK)
	Begin
		If rising_edge(PCLK) Then
			If (reset = '1') Then
				cap_req_ff1 <= '0';
				cap_req_ff2 <= '0';
				total_pix_p1 <= (Others => '0');
				total_pix_p2 <= (Others => '0');
			Else
				cap_req_ff1 <= camera_control_reg(0);
				cap_req_ff2 <= cap_req_ff1;

				total_pix_p1 <= total_pixels_clk;
				total_pix_p2 <= total_pix_p1;
			End If;
		End If;
	End Process;

	--Generate a one-cycle capture start pulse on rising edge of cap_req_ff2
	--Only trigger when FSM is idle
	Process (PCLK)
	Begin
		If rising_edge(PCLK) Then
			If (reset = '1') Then
				cap_start_pulse <= '0';
				cap_req_prev_pclk <= '0';
			Else
				cap_start_pulse <= '0';
				If (cap_busy_pclk = '0' And cap_req_ff2 = '1' And cap_req_prev_pclk = '0') Then
					cap_start_pulse <= '1';
				End If;
				cap_req_prev_pclk <= cap_req_ff2;
			End If;
		End If;
	End Process;
	--Sync busy/done back to clk domain
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If reset = '1' Then
				cap_busy_c1 <= '0';
				cap_busy_c2 <= '0';
				cap_done_c1 <= '0';
				cap_done_c2 <= '0';
			Else
				cap_busy_c1 <= cap_busy_pclk;
				cap_busy_c2 <= cap_busy_c1;
				cap_done_c1 <= cap_done_pclk;
				cap_done_c2 <= cap_done_c1;
			End If;
		End If;
	End Process;

	--Update camera status + auto-clear control bit
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If reset = '1' Then
				camera_status_reg <= (Others => '0');
			Else
				camera_status_reg(0) <= camera_busy; --busy
				If cap_done_c2 = '1' Then
					camera_status_reg(1) <= '1'; --done sticky
					--camera_control_reg(0) <= '0';    --self-clear capture bit
					--Camera control reg is reset in Ada code
				Else
					camera_status_reg(1) <= '0';
				End If;
				camera_status_reg(4 Downto 2) <= cap_state_dbg_c2; --FSM state
				camera_status_reg(5) <= cap_req_seen_c2; --saw capture request in PCLK
				camera_status_reg(6) <= saw_vsync_high_c2; --saw VSYNC high
				camera_status_reg(7) <= saw_vsync_edge_c2; --saw any VSYNC edge
				camera_status_reg(8) <= saw_href_edge_c2; --saw any HREF edge
				camera_status_reg(9) <= saw_pclk_edge_clk; --saw any PCLK edge in CLK
			End If;
		End If;
	End Process;

	--Set image resolution using the image resolution register
	--Also compute how many 32-bit words the master must read to fetch all Y pixels
	Process (clk)
		Variable pixels : unsigned(31 Downto 0);
		Variable words : unsigned(31 Downto 0);
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				total_pixels_clk <= to_unsigned(MAX_DIM * MAX_DIM, 32);
				master_words_to_read_reg <= (Others => '0');
			Else
				--pixels = width * height
				pixels := unsigned(image_resolution_reg(15 Downto 0)) *
					unsigned(image_resolution_reg(31 Downto 16));
				total_pixels_clk <= pixels;

				--words = ceil(pixels / 4)
				words := pixels / 4;
				If (pixels(1 Downto 0) /= "00") Then
					words := words + 1;
				End If;

				master_words_to_read_reg <= Std_ulogic_vector(words);
			End If;
		End If;
	End Process;
	--Image capture FSM
	Process (PCLK)
		--Local variables to build the current 32-bit word and maintain
		--byte/phase/pixel counters without multiple signal read-modify-write
		Variable v_word : Std_ulogic_vector(31 Downto 0);
		Variable v_byte_idx : unsigned(1 Downto 0);
		Variable v_yuv_phase : unsigned(1 Downto 0);
		Variable v_pix_cnt : unsigned(31 Downto 0);
		Variable is_full_word : Boolean;
	Begin
		If rising_edge(PCLK) Then
			If (reset = '1') Then
				--Latches
				vsync_lat <= '0';
				href_lat <= '0';
				data_lat <= (Others => '0');
				vsync_prev <= '0';

				--FSM and status
				cap_state <= CAP_IDLE;
				cap_busy_pclk <= '0';
				cap_done_pclk <= '0';

				--Capture bookkeeping
				yuv_phase <= (Others => '0');
				y_word_buf <= (Others => '0');
				y_byte_idx <= (Others => '0');
				y_word_index <= (Others => '0');
				y_pixel_count <= (Others => '0');

				cam_to_buffer_write_signal <= '0';
				cam_to_buffer_index <= (Others => '0');
				cam_to_buffer_data <= (Others => '0');

				--Debug sticky flags (PCLK domain)
				cap_req_seen_pclk <= '0';
				saw_vsync_high_pclk <= '0';
				saw_vsync_edge_pclk <= '0';
				saw_href_edge_pclk <= '0';

			Else
				--An edge occured if previously latched signals do not match current values
				If (VSYNC /= vsync_lat) Then
					saw_vsync_edge_pclk <= '1';
				End If;

				If (HREF /= href_lat) Then
					saw_href_edge_pclk <= '1';
				End If;

				--Normal latching for FSM edge detection
				vsync_prev <= vsync_lat;
				vsync_lat <= VSYNC;
				href_lat <= HREF;
				data_lat <= Data;

				cam_to_buffer_write_signal <= '0';
				cap_done_pclk <= '0';

				--Record seeing a capture request in the PCLK domain
				If (cap_req_ff2 = '1') Then
					cap_req_seen_pclk <= '1';
				End If;

				--Record seeing VSYNC high
				If (vsync_lat = '1') Then
					saw_vsync_high_pclk <= '1';
				End If;

				--Load current register values into variables
				v_word := y_word_buf;
				v_byte_idx := y_byte_idx;
				v_yuv_phase := yuv_phase;
				v_pix_cnt := y_pixel_count;

				cap_state_dbg_pclk <= "000"; --CAP_IDLE by default
				Case cap_state Is

						--Idle until we see an image capture request
					When CAP_IDLE =>
						cap_busy_pclk <= '0';
						cap_state_dbg_pclk <= "000"; --0 = IDLE
						cam_to_buffer_write_signal <= '0';
						cam_to_buffer_index <= (Others => '0');
						--Stay here until a capture is requested
						If (cap_start_pulse = '1') Then
							--Reset counters for a fresh frame
							v_word := (Others => '0');
							v_byte_idx := (Others => '0');
							v_yuv_phase := (Others => '0');
							v_pix_cnt := (Others => '0');
							y_word_index <= (Others => '0');

							cap_busy_pclk <= '1';
							cap_state <= CAP_ARM;
							cap_state_dbg_pclk <= "001"; --1 = ARM
						End If;

						--Wait for a VSYNC edge
					When CAP_ARM =>
						cap_state_dbg_pclk <= "001"; --1 = ARM
						If (vsync_prev = '0' And vsync_lat = '1') Then
							--saw VSYNC go high. Wait for it to go low
							Null;
							--Need to detect VSYNC falling edge (vsync now low after a high)
							--Frame starts after a VSYNC pulse
						Elsif (vsync_prev = '1' And vsync_lat = '0') Then
							v_yuv_phase := (Others => '0');
							cap_state <= CAP_CAPTURE; --Skip to CAP_CAPTURE
						End If;

						--NOT using this state anymore. Each HREF pulse corresponds to pixel data. Waiting here means letting the first pixel data go to waste
					When CAP_WAIT_ACTIVE =>
						cap_state_dbg_pclk <= "010"; --2 = WAIT_ACTIVE
						If (href_lat = '1') Then
							v_yuv_phase := (Others => '0');
							cap_state <= CAP_CAPTURE;
						End If;

						--Capture the Y bytes in the data stream when HREF is high
					When CAP_CAPTURE =>
						cap_state_dbg_pclk <= "011"; --3 = CAPTURE
						--If VSYNC falls before we reach requested pixels, terminate
						If (vsync_prev = '1' And vsync_lat = '0') Then
							cap_state <= CAP_DONE;

						Else
							If (href_lat = '1') Then

								If ((v_yuv_phase = "00") Or (v_yuv_phase = "10")) Then
									--Place this Y byte into the current 32-bit word at byte index
									Case v_byte_idx Is
										When "00" =>
											v_word(7 Downto 0) := data_lat;
										When "01" =>
											v_word(15 Downto 8) := data_lat;
										When "10" =>
											v_word(23 Downto 16) := data_lat;
										When Others =>
											v_word(31 Downto 24) := data_lat;
									End Case;

									is_full_word := (v_byte_idx = "11");

									--Increment pixel counter
									v_pix_cnt := v_pix_cnt + 1;

									--If we have a full word OR this was the last pixel,
									--write the word into the image buffer.
									If (is_full_word Or (v_pix_cnt = total_pix_p2 - 1)) Then
										cam_to_buffer_index <= y_word_index;
										cam_to_buffer_data <= v_word;
										cam_to_buffer_write_signal <= '1';

										y_word_index <= y_word_index + 1;
										v_byte_idx := (Others => '0');
									Else
										v_byte_idx := v_byte_idx + 1;
									End If;

									--Stop after total requested pixels
									If ((v_pix_cnt = total_pix_p2 - 1)) Then
										cap_state <= CAP_DONE;
									End If;
								End If;

								--Advance YUV phase (wrap at 4)
								If (v_yuv_phase = "11") Then
									v_yuv_phase := (Others => '0');
								Else
									v_yuv_phase := v_yuv_phase + 1;
								End If;

							Else
								--HREF low: outside active line, restart byte/phase alignment
								v_yuv_phase := (Others => '0');
							End If;
						End If;

						--Capture complete
					When CAP_DONE =>
						cap_state_dbg_pclk <= "100"; --4 = DONE
						cap_busy_pclk <= '0';
						cap_done_pclk <= '1';

						cam_to_buffer_write_signal <= '0';
						cam_to_buffer_index <= (Others => '0');

						--Wait for start bit to be cleared before tring to capture a new image
						If (cap_req_ff2 = '0') Then
							cap_done_pclk <= '0';
							cap_state <= CAP_IDLE;
						End If;

				End Case;

				--Store varible data in registers
				y_word_buf <= v_word;
				y_byte_idx <= v_byte_idx;
				yuv_phase <= v_yuv_phase;
				y_pixel_count <= v_pix_cnt;

			End If;
		End If;
	End Process;

	--Sync capture FSM debug state back to clk domain
	Process (clk)
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				cap_state_dbg_c1 <= (Others => '0');
				cap_state_dbg_c2 <= (Others => '0');
			Else
				cap_state_dbg_c1 <= cap_state_dbg_pclk;
				cap_state_dbg_c2 <= cap_state_dbg_c1;
			End If;
		End If;
	End Process;

	--Sync cap_req_seen back to clk domain
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If (reset = '1') Then
				cap_req_seen_c1 <= '0';
				cap_req_seen_c2 <= '0';
			Else
				cap_req_seen_c1 <= cap_req_seen_pclk;
				cap_req_seen_c2 <= cap_req_seen_c1;
			End If;
		End If;
	End Process;

	--Sync PCLK into clk domain and detect any edge
	Process (clk)
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				pclk_sync_1 <= '0';
				pclk_sync_2 <= '0';
				saw_pclk_edge_clk <= '0';
			Else
				pclk_sync_1 <= PCLK;
				pclk_sync_2 <= pclk_sync_1;

				--If the two sampled values differ, we saw a PCLK edge
				If (pclk_sync_1 /= pclk_sync_2) Then
					saw_pclk_edge_clk <= '1';
				End If;
			End If;
		End If;
	End Process;

	--Sync saw_vsync_edge back to clk domain
	Process (clk)
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				saw_vsync_edge_c1 <= '0';
				saw_vsync_edge_c2 <= '0';
			Else
				saw_vsync_edge_c1 <= saw_vsync_edge_pclk;
				saw_vsync_edge_c2 <= saw_vsync_edge_c1;
			End If;
		End If;
	End Process;

	--Sync saw_href_edge back to clk domain
	Process (clk)
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				saw_href_edge_c1 <= '0';
				saw_href_edge_c2 <= '0';
			Else
				saw_href_edge_c1 <= saw_href_edge_pclk;
				saw_href_edge_c2 <= saw_href_edge_c1;
			End If;
		End If;
	End Process;
	--The acknowledgement process is combined with the tensor multiplex select logic and register reads
	Process (clk)
		Variable is_valid : Std_ulogic;
		Variable is_tensor : Std_ulogic;

	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				ack_r <= '0';
				wb_rsel <= (Others => '0');
				reg_rdata <= (Others => '0');
			Else
				ack_r <= '0';
				If (wb_req = '1') Then
					--Default
					is_valid := '0';
					is_tensor := '0';
					wb_rsel <= (Others => '0');
					reg_rdata <= (Others => '0');

					--Register reads
					If (i_wb_addr = CAMERA_CONTROL_ADDRESS) Then
						is_valid := '1';
						reg_rdata <= camera_control_reg;
					Elsif (i_wb_addr = CAMERA_STATUS_ADDRESS) Then
						is_valid := '1';
						reg_rdata <= camera_status_reg;
					Elsif (i_wb_addr = IMAGE_FORMAT_ADDRESS) Then
						is_valid := '1';
						reg_rdata <= image_format_reg;
					Elsif (i_wb_addr = IMAGE_RESOLUTION_ADDRESS) Then
						is_valid := '1';
						reg_rdata <= image_resolution_reg;
					Elsif (i_wb_addr = MASTER_WORDS_TO_READ_ADDRESS) Then
						is_valid := '1';
						reg_rdata <= master_words_to_read_reg;
					Elsif (i_wb_addr = SCCB_PROGRAM_STATUS_REG_ADDRESS) Then
						is_valid := '1';
						reg_rdata <= sccb_program_status_reg;
						--Tensor windows are valid only when idle (npu_busy='0')
					Elsif (unsigned(i_wb_addr) >= unsigned(IMAGE_BUFFER_BASE) And
						unsigned(i_wb_addr) < unsigned(IMAGE_BUFFER_BASE) + to_unsigned(TENSOR_BYTES, 32)) Then
						is_valid := '1';
						is_tensor := '1';
						wb_rsel <= "001";
					End If;
					--Gate image buffer while camera is busy
					If (is_valid = '1') Then
						If (is_tensor = '1' And camera_busy = '1') Then
							ack_r <= '0';
						Else
							ack_r <= '1';
						End If;
					End If;
				End If;
			End If;
		End If;
	End Process;

	--Sync saw_vsync_high back to clk domain
	Process (clk)
	Begin
		If rising_edge(clk) Then
			If reset = '1' Then
				saw_vsync_high_c1 <= '0';
				saw_vsync_high_c2 <= '0';
			Else
				saw_vsync_high_c1 <= saw_vsync_high_pclk;
				saw_vsync_high_c2 <= saw_vsync_high_c1;
			End If;
		End If;
	End Process;
	--Wishbone register write process
	Process (clk)
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				image_format_reg <= (Others => '0');
				image_resolution_reg <= (Others => '0');
			Else
				If (wb_req = '1' And i_wb_we = '1') Then
					--Registers are always writable (NPU busy status does not matter)
					If (i_wb_addr = CAMERA_CONTROL_ADDRESS) Then
						camera_control_reg <= i_wb_data;
					Elsif (i_wb_addr = CAMERA_STATUS_ADDRESS) Then
						Null; --Wishbone does not write to status register
					Elsif (i_wb_addr = IMAGE_FORMAT_ADDRESS) Then
						image_format_reg <= i_wb_data;
					Elsif (i_wb_addr = IMAGE_RESOLUTION_ADDRESS) Then
						image_resolution_reg <= i_wb_data;
					Elsif (i_wb_addr = MASTER_WORDS_TO_READ_ADDRESS) Then
						Null;
					End If;
				End If;
			End If;
		End If;
	End Process;

	With wb_rsel Select
		o_wb_data <= reg_rdata When "000",
		image_buffer_wb_rdata When Others;
	--Image buffer: WB read (when idle) + camera write
	Process (clk)
		Variable tensor_offset : Natural;
		Variable w_index : Natural;
		Variable byte_sel : Natural Range 0 To 3;
		Variable word_tmp : Std_ulogic_vector(31 Downto 0);
	Begin
		If (rising_edge(clk)) Then
			If (reset = '1') Then
				image_buffer_wb_rdata <= (Others => '0');
			Else
				If (camera_busy = '0') Then
					--WB read port
					If (wb_req = '1' And
						unsigned(i_wb_addr) >= unsigned(IMAGE_BUFFER_BASE) And unsigned(i_wb_addr) < unsigned(IMAGE_BUFFER_BASE) + to_unsigned(TENSOR_BYTES, 32)) Then
						tensor_offset := get_tensor_offset(i_wb_addr, IMAGE_BUFFER_BASE);
						If (tensor_offset < TENSOR_WORDS) Then
							image_buffer_wb_rdata <= image_buffer(tensor_offset);
						Else
							image_buffer_wb_rdata <= (Others => '0');
						End If;
					End If;
				End If;
			End If;
		End If;
	End Process;

	--PCLK camera write
	--ECP5 supports dual-clock BRAM  (many FPGAs do)
	--We write on PCLK
	Process (PCLK)
	Begin
		If (rising_edge(PCLK)) Then
			If (reset = '1') Then
				--Commented out to void multiple driver error
				--cam_to_buffer_data <= (Others => '0');
				--cam_to_buffer_index <= (Others => '0');
			Else
				If (cam_to_buffer_write_signal = '1') Then
					If (to_integer(cam_to_buffer_index) < TENSOR_WORDS) Then
						image_buffer(to_integer(cam_to_buffer_index)) <= cam_to_buffer_data;
					End If;
				End If;
			End If;
		End If;
	End Process;
End Architecture;