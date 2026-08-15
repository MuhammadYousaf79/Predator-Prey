import serial

ser = serial.Serial('COM4',115200)

rx_file = "script/rx_file.csv"


with open(rx_file, "w") as f:
    while True:
        for i in range(4):
            data = ser.read()
            if data:
                f.write(hex(ord(data)))
        f.write(",")
        for i in range(4):
            data = ser.read()
            if data:
                f.write(hex(ord(data)))
        f.write("\n")
