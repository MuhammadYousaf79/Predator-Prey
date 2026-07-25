import matplotlib.pyplot as plt

prey = [2]
predator = [1]

alpha = 1.0
beta = 0.5
gamma = 1.0
delta = 0.5

# 1. LOWER the step size so the simulation doesn't explode
h = 0.001 

for i in range(17500):
    # 2. GRAB current values so they don't change mid-calculation
    current_prey = prey[-1]
    current_predator = predator[-1]
    
    # Calculate rates using ONLY current values
    d_prey = (alpha * current_prey) - (beta * current_prey * current_predator)
    d_predator = (gamma * current_prey * current_predator) - (delta * current_predator)
    
    # 3. APPEND the new values
    prey.append(current_prey + h * d_prey)
    predator.append(current_predator + h * d_predator)

# --- Plotting ---
plt.figure()
plt.plot(prey, label="Prey", color="blue")
plt.plot(predator, label="Predator", color="red")
plt.title("Prey and Predator Populations Over Time")
plt.xlabel("Time steps")
plt.ylabel("Population")
plt.legend()

plt.figure()
plt.plot(prey, predator, color="purple")
plt.title("Phase Portrait (Prey vs Predator)")
plt.xlabel("Prey Population")
plt.ylabel("Predator Population")

plt.tight_layout()
plt.show()