import matplotlib.pyplot as plt
import csv

csv_file_path = "predator_prey.csv"

prey = []
predator = []

with open(csv_file_path) as csv_file:
    csv_reader = csv.reader(csv_file, delimiter=',')
    for row in csv_reader:
        prey.append(float(row[0])/65536)
        predator.append(float(row[1])/65536)

plt.figure()
plt.plot(prey)
plt.title("prey")
plt.xlabel("prey")

plt.figure()
plt.plot(predator)
plt.title("predator")
plt.xlabel("predator")

plt.figure()
plt.plot(prey, predator)
plt.title("prey vs predator")
plt.xlabel("prey")
plt.ylabel("predator")

plt.show()