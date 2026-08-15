import serial

ser = serial.Serial('COM4',115200)

rx_file = "script/rx_file.csv"


with open(rx_file, "w") as f:
    f.write("0x")
    while True:
        for i in range(4):
            data = ser.read()
            if data:
                f.write(f"{data[0]:02X}")
        f.write(",0x")
        for i in range(4):
            data = ser.read()
            if data:
                f.write(f"{data[0]:02X}")
        f.write("\n0x")
