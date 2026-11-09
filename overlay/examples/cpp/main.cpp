#include <cstdio>

int add(int a, int b) {
    int sum = a + b;
    return sum;
}

int main() {
    int answer = add(20, 22);
    std::printf("answer=%d\n", answer);
    return answer == 42 ? 0 : 1;
}
