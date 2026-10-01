import serial
import struct
import time
import matplotlib.pyplot as plt

# --- Configuration ---
PORT = 'COM4'
BAUD = 115200
TOTAL_STEPS = 1_000_000
Q24_SCALE = 2**24  # 16777216.0 for Q8.24 conversion

# Lotka-Volterra parameters for PC-side Prey calculation (Euler method)
ALPHA = 1.0
BETA  = 0.5
H     = 0.001

def main():
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    # time.sleep(1.0)  # Allow port to stabilize

    print("=" * 60)
    print(f"Connected to {PORT} at {BAUD} baud.")
    print("Press 's' and press [Enter] to start the simulation...")
    print("=" * 60)

    while True:
        user_input = input(">> ").strip().lower()
        if user_input == 's':
            break
        print("Invalid input. Type 's' to start.")

    # Purge any stale bytes accumulated before start
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # Initial prey condition in Q8.24 (2.0)
    prey_int = int(2.0 * Q24_SCALE)

    prey_history = []
    predator_history = []

    print("\nStarting execution loop...")
    start_time = time.time()

    try:
        for step in range(TOTAL_STEPS):
            # 1. Send exactly 4 raw bytes to FPGA (signed 32-bit big-endian)
            raw_response = ser.read(4)
            ser.write(struct.pack('>i', prey_int))
            ser.flush()

            # 2. Read exactly 4 raw bytes back from FPGA
            if len(raw_response) < 4:
                print(f"\n[ERROR] Sync/Timeout at step {step}: received {len(raw_response)} bytes.")
                if len(raw_response) > 0:
                    print(f"Raw residual buffer: {raw_response.hex()}")
                break

            # 3. Unpack received predator integer
            predator_int = struct.unpack('>i', raw_response)[0]

            # 4. Convert to floating point
            prey_val = prey_int / Q24_SCALE
            predator_val = predator_int / Q24_SCALE

            prey_history.append(prey_val)
            predator_history.append(predator_val)

            if step % 100 == 0:
                print(f"Step {step:04d} | Prey: {prey_val:8.4f} | Predator: {predator_val:8.4f}")

            # 5. Compute next Prey iteration on PC:
            # dx/dt = alpha * x - beta * x * y
            # x_next = x + h * (alpha * x - beta * x * y)
            d_prey = (ALPHA * prey_val) - (BETA * prey_val * predator_val)
            prey_next_val = prey_val + (H * d_prey)

            # Convert back to signed Q8.24 integer for the next FPGA transfer
            prey_int = int(prey_next_val * Q24_SCALE)
            
            # Clamp to 32-bit signed limits
            if prey_int > 2147483647:
                prey_int = 2147483647
            elif prey_int < -2147483648:
                prey_int = -2147483648

    except KeyboardInterrupt:
        print("\nExecution aborted by user.")
    finally:
        ser.close()
        elapsed = time.time() - start_time
        print(f"Finished in {elapsed:.2f} seconds ({len(prey_history)} points received). Port closed.")

    # --- Plotting ---
    if len(prey_history) > 0:
        time_axis = [i * H for i in range(len(prey_history))]

        plt.figure(figsize=(12, 5))

        # Subplot 1: Time Series
        plt.subplot(1, 2, 1)
        plt.plot(time_axis, prey_history, label='Prey (PC)', color='blue')
        plt.plot(time_axis, predator_history, label='Predator (FPGA)', color='red')
        plt.title('Lotka-Volterra Time Response')
        plt.xlabel('Time (s)')
        plt.ylabel('Population')
        plt.grid(True)
        plt.legend()

        # Subplot 2: Phase Plane
        plt.subplot(1, 2, 2)
        plt.plot(prey_history, predator_history, color='purple')
        plt.title('Phase Space Trajectory')
        plt.xlabel('Prey (x)')
        plt.ylabel('Predator (y)')
        plt.grid(True)

        plt.tight_layout()
        plt.show()

if __name__ == '__main__':
    main()