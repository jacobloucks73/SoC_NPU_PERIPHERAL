--Wrapper for I2C controller to write to the OV5640 registers at bootup using values from a table
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;

ENTITY sccb_i2c_wrapper IS
	GENERIC (
		INPUT_CLK_HZ : INTEGER := 72_000_000;
		BUS_CLK_HZ : INTEGER := 400_000
	);
	PORT (
		clk : IN Std_ulogic;
		reset : IN Std_ulogic;
		--SCCB pins
		SIO_C : INOUT Std_ulogic;
		SIO_D : INOUT Std_ulogic;
		--control
		start : IN Std_ulogic; --1 to start
		busy : OUT Std_ulogic; --0 = idle. 1 = busy
		done : OUT Std_ulogic; --0 = not done. 1 = busy
		err : OUT Std_ulogic --Included because the I2C controller has it
	);
END;

ARCHITECTURE rtl OF sccb_i2c_wrapper IS

	--I2C controller
	COMPONENT i2c_controller IS
		GENERIC (
			input_clk : INTEGER := 72_000_000; --input clock speed from user logic in Hz
			bus_clk : INTEGER := 400_000 --speed of I2C bus. OV5640 supports 400KHz (fast mode).
		);
		PORT (
			clk : IN Std_ulogic; --system clock
			reset_n : IN Std_ulogic; --Needs to be active low
			ena : IN Std_logic; --0= no transaction inititated. 1 : latches in addr, rw, and data_wr to initiate a transaction
			--If ena is high at the end of a transaction, then a new address, read/write command, and data are latched in to continue a transaction
			addr : IN Std_logic_vector (6 DOWNTO 0); --Address of target slave
			rw : IN Std_logic; --0: write command. 1 = read command
			data_wr : IN Std_logic_vector (7 DOWNTO 0); --data to transmit if rw = 0 (write)
			data_rd : OUT Std_logic_vector (7 DOWNTO 0); --data to read if rw = 1 (read)
			busy : OUT Std_logic; --0: I2c master is idle and last read command data is available on data_rd. 1 = command has been latched and trasnaction is in progress
			ack_error : OUT Std_logic; --0: no acknowledge errors. 1 = error
			SDA : INOUT Std_logic; --Data line
			SCL : INOUT Std_logic --Serial clock line
		);
	END COMPONENT;

	--Signals for I2C cotnroller
	SIGNAL i2c_ena : Std_logic;
	SIGNAL device_addr : Std_logic_vector(6 DOWNTO 0) := "0111100"; --OV5640 address = 0x78. For I2C (SCCB), do 0x78>>1 = 0x3c
	SIGNAL i2c_rw : Std_logic := '0';
	SIGNAL i2c_data_wr : Std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
	SIGNAL i2c_data_rd : Std_logic_vector(7 DOWNTO 0) := (OTHERS => '0'); --No use, but created in case
	SIGNAL i2c_busy : Std_logic;
	SIGNAL i2c_ack_error : Std_logic;
	--ROM Tables
	TYPE ov5640_reg_addr_arr IS ARRAY (NATURAL RANGE <>) OF Std_logic_vector(15 DOWNTO 0); --OV5640 address array type
	TYPE ov5640_reg_data_arr IS ARRAY (NATURAL RANGE <>) OF Std_logic_vector(7 DOWNTO 0); --OV5640 data arrays
	SIGNAL ov5640_reg_addr : ov5640_reg_addr_arr(0 TO 45) := (
		x"3103", x"3008", x"3008", 
		x"3017", x"3018", 
		x"4300", 
		x"501F", 
		x"4740", 

		--Image enhancement registers
		x"3503", --AEC and AGC enable register
		x"3A00", --AEC settings
		x"5001", --ISP control
		x"5003", --ISP: draw window for AF (optional)

		--AEC (brightness control). Refer to the applications datasheet to see the effects. The default configuration and the datasheet values do not match. Change as per your experience/use case
		x"3A0F", --Stable range in high
		x"3A10", --Stable range in low
		x"3A1B", --Stable range out high
		x"3A1E", --Stable range out low
		x"3A11", --Fast zone high
		x"3A1F", --Fast zone low

		--Timing window registers
		x"3800", x"3801", x"3802", x"3803", 
		x"3804", x"3805", x"3806", x"3807", 
		x"3808", x"3809", x"380A", x"380B", 
		x"380C", x"380D", x"380E", x"380F", 
		x"3810", x"3811", x"3812", x"3813", 
		x"3814", x"3815", 

		x"3820", x"3821", 
		x"4004", --Black level Configuration (BLC) settings
		x"503D", 
		x"300E", 
		x"3008"
	);

	SIGNAL ov5640_reg_data : ov5640_reg_data_arr(0 TO 45) := (
		x"11", x"82", x"42", --0x3103, 0x3008, 0x3008 (first reset and then software power down)
		x"FF", x"FF", --0x3017, 0x3018. (VSYNC is an output pin and must use a register-controlled value)
		x"30", --0x4300 (YUV422 YUYV)
		x"00", --0x501F (ISP YUV422)
		x"20", --0x4740 for signal polarity (PCLK high, VSYNC/HREF low)

		x"00", --0x3503 (AEC/AGC auto (0 = auto))
		x"38", --0x3A00 (AEC on, banding etc)
		x"A3", --0x5001 (Special effects, Scaling, and AWB enabled)
		x"08", --0x5003 (Disable all binning and window settings)

		--AEC (brightness control). Refer to the applications datasheet to see the effects. The default configuration and the datasheet values do not match. Change as per your experience/use case
		--The following follows the 1 EV profile
		x"50", --0x3A0F
		x"48", --0x3A10
		x"50", --0x3A1B
		x"48", --0x3A1E
		x"90", --0x3A11
		x"20", --0x3A1F

		--Settings for 100x100 window
		--Best to program all because it makes (made) experimenting easier
		x"00", x"08", x"00", x"02", --0x3800 - 0x3803
		x"0A", x"37", x"07", x"A1", --0x3804 - 0x3807
		x"00", x"64", x"00", x"64", --0x3808 - 0x380B (actual resolution)
		x"06", x"14", x"03", x"E8", --0x380C - 0x380F
		x"00", x"04", x"00", x"02", --0x3810 - 0x3813
		x"31", x"31", --0x3814 and 0x3815

		x"47", x"01", --0x3820, 0x3821 (flip and mirror settings)
		x"06", --0x4004 (BLC 6 is good. Without this the images were very dark)
		x"00", --0x503D (Test pattern)
		x"58", --0x300E (select DVP)
		x"02" --0x3008 wake from soft power down
	);

	SIGNAL table_length : NATURAL := ov5640_reg_addr'Length; --ROM table Length

	SIGNAL table_index : NATURAL := 0;
	SIGNAL reg_addr_loaded : Std_logic_vector(15 DOWNTO 0); --Loaded address from ROM table
	SIGNAL reg_data_loaded : Std_logic_vector(7 DOWNTO 0); --Loaded register data

	--BRAM inference hints
	ATTRIBUTE ram_style : STRING;
	ATTRIBUTE syn_ramstyle : STRING;

	ATTRIBUTE ram_style OF ov5640_reg_addr : SIGNAL IS "BLOCK";
	ATTRIBUTE ram_style OF ov5640_reg_data : SIGNAL IS "BLOCK";

	ATTRIBUTE syn_ramstyle OF ov5640_reg_addr : SIGNAL IS "block_ram";
	ATTRIBUTE syn_ramstyle OF ov5640_reg_data : SIGNAL IS "block_ram";

	--Delay counter for power-up timing

	CONSTANT CYCLES_5MS : INTEGER := (INPUT_CLK_HZ / 1000) * 5; --5ms delay
	SIGNAL powerup_delay_counter : INTEGER RANGE 0 TO CYCLES_5MS := 0;
	--FSM
	--3-phase write transmission according to the user manual: ID address -> High byte of 16- bit address -> Low byte of 16-bit address -> Value
	TYPE state_t IS (SCCB_IDLE, SCCB_BEGIN, SCCB_ADDR_WRITE_UPPER, SCCB_ADDR_LOAD_LOWER, SCCB_ADDR_WRITE_LOWER, SCCB_ADDR_WAIT, SCCB_DATA_LOAD, SCCB_DATA_WAIT, SCCB_DATA_WRITE, SCCB_STOP_WAIT, SCCB_WAIT_5MS, SCCB_DONE);
	SIGNAL state : state_t := SCCB_IDLE;
BEGIN
	busy <= '1' WHEN (state /= SCCB_IDLE AND state /= SCCB_DONE) ELSE '0';
	done <= '1' WHEN (state = SCCB_DONE) ELSE '0';
	err <= i2c_ack_error;
	i2c_controller_inst : i2c_controller
	PORT MAP(
		clk => clk, 
		reset_n => reset, 
		ena => i2c_ena, 
		addr => device_addr, 
		rw => i2c_rw, 
		data_wr => i2c_data_wr, 
		data_rd => i2c_data_rd, 
		busy => i2c_busy, 
		ack_error => i2c_ack_error, 
		SDA => SIO_D, 
		SCL => SIO_C
	);

	--FSM Process
	--3-phase write transmission according to the user manual: ID address -> High byte of 16- bit address -> Low byte of 16-bit address -> Value
	--I2C is a stricter protocol than SCCB: Start -> data address -> register addresses -> data. The ACK bit does not matter in SCCB
	--The FSM is only worked through once, when start rise is 1
	PROCESS (clk)
	BEGIN
		IF rising_edge(clk) THEN
			IF (reset = '1') THEN
				table_index <= 0;
				state <= SCCB_IDLE;
				i2c_ena <= '0';
				i2c_rw <= '0';
				i2c_data_wr <= (OTHERS => '0');
				powerup_delay_counter <= 0;
			ELSE
				CASE state IS
					WHEN SCCB_IDLE => 
						--Idle until start is asserted
						i2c_ena <= '0';
						IF (start = '1') THEN
							table_index <= 0;
							state <= SCCB_BEGIN;
						END IF;

					WHEN SCCB_BEGIN
						=> 

						--We want to send two address (upper and lower byte), so we must ensure ENA remains high. the i2C controller hndles the device address logic
						--Begin transaction. First byte after device address is upper byte of reg address so load that
						i2c_rw <= '0'; --Write command
						i2c_ena <= '1'; --Latched to initiate a transaction
						i2c_data_wr <= reg_addr_loaded(15 DOWNTO 8); --Get the upper byte of the address
						state <= SCCB_ADDR_WRITE_UPPER;

					WHEN SCCB_ADDR_WRITE_UPPER => 
						--Wait until controller indicates transaction has started by setting busy
						IF (i2c_ack_error = '1') THEN --OV5640 is unknown territory. I am using the error signal.
							i2c_ena <= '0'; --Do not start a transaction if there is an error
							state <= SCCB_DONE; --Done if there is an error
						ELSIF (i2c_busy = '1') THEN --Only load the lower byte once the upper byte is being uploaded. Otherwise, we will problematically skip over the upper byte of the reg address
							--Preload next byte while controller is busy with current byte
							state <= SCCB_ADDR_LOAD_LOWER;
						END IF;

					WHEN SCCB_ADDR_LOAD_LOWER => 
						--Load lower byte of reg address while upper address byte is being sent
						i2c_data_wr <= reg_addr_loaded(7 DOWNTO 0);
						state <= SCCB_ADDR_WAIT;

					WHEN SCCB_ADDR_WAIT => 
						--Wait until busy is 0 indicating the byte has been transmitted
						IF (i2c_ack_error = '1') THEN --OV5640 is unknown territory. I am using the error signal.
							i2c_ena <= '0'; --Do not start a transaction if there is an error
							state <= SCCB_DONE; --Done if there is an error
						ELSIF (i2c_busy = '0') THEN
							state <= SCCB_ADDR_WRITE_LOWER;
						END IF;

					WHEN SCCB_ADDR_WRITE_LOWER => 
						--Load data byte while lower reg-address byte is sent
						IF (i2c_ack_error = '1') THEN --OV5640 is unknown territory. I am using the error signal.
							i2c_ena <= '0'; --Do not start a transaction if there is an error
							state <= SCCB_DONE; --Done if there is an error
						ELSIF (i2c_busy = '1') THEN
							--i2c_data_wr <= reg_data_loaded;
							state <= SCCB_DATA_LOAD;
						END IF;

					WHEN SCCB_DATA_LOAD => 
						--Load data byte until the lower address byte is sent
						i2c_data_wr <= reg_data_loaded;
						state <= SCCB_DATA_WAIT;

					WHEN SCCB_DATA_WAIT => 
						--Wait until busy is 0 indicating the byte has been transmitted
						IF (i2c_ack_error = '1') THEN --OV5640 is unknown territory. I am using the error signal.
							i2c_ena <= '0'; --Do not start a transaction if there is an error
							state <= SCCB_DONE; --Done if there is an error
						ELSIF (i2c_busy = '0') THEN
							--Deassert ena so the controller will STOP after the data byte
							i2c_ena <= '0';
							state <= SCCB_DATA_WRITE;
						END IF;

					WHEN SCCB_DATA_WRITE => 
						--Wait for the data-byte transfer to actually start,
						--then deassert ENA so the controller will STOP after the data byte.
						IF (i2c_busy = '1') THEN
							i2c_ena <= '0'; --No data after this byte
							state <= SCCB_STOP_WAIT;
						END IF;

					WHEN SCCB_STOP_WAIT => 
						--Wait for transaction to complete (data byte finished + STOP condition)
						IF (i2c_busy = '0') THEN
							IF (table_index = table_length - 1) THEN
								state <= SCCB_DONE;
							ELSE
								table_index <= table_index + 1;
								state <= SCCB_WAIT_5MS;
							END IF;
						END IF;

					WHEN SCCB_WAIT_5MS => 
						--Wait for 5ms before writing to the next register
						IF (powerup_delay_counter < CYCLES_5MS - 1) THEN
							powerup_delay_counter <= powerup_delay_counter + 1;
						ELSE
							powerup_delay_counter <= 0;
							state <= SCCB_BEGIN;
						END IF;

					WHEN SCCB_DONE => 
						--Done
						i2c_ena <= '0';
						IF (start = '0') THEN
							state <= SCCB_IDLE;
						END IF;
				END CASE;
			END IF;
		END IF;
	END PROCESS;

	--Read address ROM table
	PROCESS (clk)
	BEGIN
			IF (rising_edge(clk)) THEN
				IF (reset = '1') THEN
					reg_addr_loaded <= (OTHERS => '0');
				ELSE
					reg_addr_loaded <= ov5640_reg_addr(table_index);
				END IF;
			END IF;
		END PROCESS;

		--Read data table
	PROCESS (clk)
	BEGIN
		IF (rising_edge(clk)) THEN
			IF (reset = '1') THEN
					reg_data_loaded <= (OTHERS => '0');
			ELSE
					reg_data_loaded <= ov5640_reg_data(table_index);
				END IF;
			END IF;
	END PROCESS;

END;