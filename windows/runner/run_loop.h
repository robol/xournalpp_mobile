#ifndef RUN_LOOP_H_
#define RUN_LOOP_H_

// A runloop that services native Windows messages.
class RunLoop {
 public:
  RunLoop();
  ~RunLoop();

  // Prevent copying
  RunLoop(RunLoop const&) = delete;
  RunLoop& operator=(RunLoop const&) = delete;

  // Runs the run loop until the application quits.
  void Run();
};

#endif  // RUN_LOOP_H_
