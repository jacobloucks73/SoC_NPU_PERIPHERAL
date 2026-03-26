with Ada.Text_IO; use Ada.Text_IO;
with Interfaces; use Interfaces;
package body Wb_Ov5640_Helper.Debug is

   procedure Print_Registers is
   begin
      Put_Line ("CTRL Reg: " & Word'Image (Read_Reg (CTRL_Addr)));
      Put_Line ("Status Reg: " & Word'Image (Read_Reg (STATUS_Addr)));
      Put_Line
        ("Image Resolution Register: "
         & Word'Image (Read_Reg (IMAGE_RESOLUTION_Addr)));
      Put_Line
        ("SCCB Programmer Register: "
         & Word'Image (Read_Reg (IMAGE_RESOLUTION_Addr)));
   end Print_Registers;

   procedure Print_Status_Register_Detail is
      S             : Word;
      St            : Natural;
      Saw           : Boolean;
      Saw_V         : Boolean;
      Saw_V_Edge    : Boolean;
      Saw_H_Edge    : Boolean;
      Saw_PCLK_Edge : Boolean;
   begin
      S := Read_Reg (STATUS_Addr);
      St := Natural (Shift_Right (Unsigned_32 (S and 16#1C#), 2));  --bits 4..2
      Saw := (S and Word (16#20#)) /= 0;                             --bit 5
      Saw_V := (S and Word (16#40#)) /= 0;                             --bit 6
      Saw_V_Edge := (S and Word (16#80#)) /= 0; --bit 7
      Saw_H_Edge := (S and Word (16#100#)) /= 0; --bit 8
      Saw_PCLK_Edge := (S and Word (16#200#)) /= 0; --bit 9

      Put_Line ("CTRL Reg:   " & Word'Image (Read_Reg (CTRL_Addr)));
      Put_Line ("Status Reg: " & Word'Image (S));
      Put_Line ("FSM state: " & Natural'Image (St));
      Put_Line ("Saw Capture Request: " & Boolean'Image (Saw));
      Put_Line ("Saw VSYNC high: " & Boolean'Image (Saw_V));
      Put_Line ("Saw VSYNC edge: " & Boolean'Image (Saw_V_Edge));
      Put_Line ("Saw HREF edge: " & Boolean'Image (Saw_H_Edge));
      Put_Line ("Saw PCLK edge: " & Boolean'Image (Saw_PCLK_Edge));
   end Print_Status_Register_Detail;

end Wb_Ov5640_Helper.Debug;
