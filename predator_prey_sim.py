import matplotlib.pyplot as plt

prey = [2]
predator = [1]

alpha = 1
beta = 0.5
gamma = 1
delta = 0.5
h = 0.001

for i in range(100_000):
    x = prey[-1] + h*((alpha*prey[-1])-(beta*prey[-1]*predator[-1]))
    y = predator[-1] + h*((gamma*prey[-1]*predator[-1])-(delta*predator[-1]))
    prey.append(x)
    predator.append(y)

plt.figure()

# plt.subplot(3,1,1)
plt.plot(prey)
plt.title("prey")
plt.ylabel("prey")

# plt.subplot(3,1,2)
plt.figure()
plt.plot(predator)
plt.title("predator")
plt.ylabel("predator")

# plt.subplot(3,1,3)
plt.figure()
plt.plot(prey,predator)
plt.title("prey vs predator")
plt.xlabel("prey")
plt.ylabel("predator")

plt.tight_layout()
plt.show()