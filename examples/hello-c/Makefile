CC = gcc
CFLAGS = -Wall -Wextra -O2
TARGET = hello-rg353v

all: $(TARGET)

$(TARGET): main.c
	$(CC) $(CFLAGS) -o $(TARGET) main.c

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)
