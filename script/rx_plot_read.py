import matplotlib.pyplot as plt
import serial

ser = serial.Serial("COM4", 115200)

prey = []
predator = []

plt.ion()

fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(8, 10))

while True:

    for j in range(1000):

        pp = "0x"

        for i in range(4):
            data = ser.read()
            if data:
                pp += f"{data[0]:02X}"

        pp = "0x02" + pp[4:]
        prey.append(int(pp, 16) / 16777216)

        pp = "0x"

        for i in range(4):
            data = ser.read()
            if data:
                pp += f"{data[0]:02X}"

        predator.append(int(pp, 16) / 16777216)

    # Update all three plots
    ax1.clear()
    ax1.plot(prey)
    ax1.set_title("Prey")
    ax1.set_xlabel("Iteration")
    ax1.set_ylabel("Population")

    ax2.clear()
    ax2.plot(predator)
    ax2.set_title("Predator")
    ax2.set_xlabel("Iteration")
    ax2.set_ylabel("Population")

    ax3.clear()
    ax3.plot(prey, predator)
    ax3.set_title("Prey vs Predator")
    ax3.set_xlabel("Prey")
    ax3.set_ylabel("Predator")

    fig.tight_layout()

    fig.canvas.draw()
    fig.canvas.flush_events()

    plt.pause(0.001)