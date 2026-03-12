FROM gcc:12-bookworm
COPY seccomp-test.c /
RUN gcc -static -o /seccomp-test /seccomp-test.c
CMD ["/seccomp-test"]
