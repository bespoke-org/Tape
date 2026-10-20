# DayTape

DayTape records time spent on reusable tasks through a continuous timeline.

## Language

**Task**:
A named activity that can be worked on repeatedly, including across different days or weeks.

**Time entry**:
A continuous stretch of time spent on one task. A task can have many time entries, and entries cannot overlap.
_Avoid_: Event, session

**Running task**:
The task currently accumulating tracked time. Only one task can run at a time.
_Avoid_: Current task, active task

**Timeline**:
The continuous horizontal strip showing recorded time, which can be browsed backward and forward.

**Now marker**:
A visual indication of the current time on the timeline. It need not remain visible while browsing other times.

**Pending continuation**:
The nine-second opportunity to reject resuming a task after returning from screen lock or sleep. Clicking OK or opening DayTape accepts it immediately. Clicking elsewhere or using other apps keeps its popup visible until the nine-second countdown finishes or Reject is clicked. Hovering over the notice freezes the remaining countdown; moving away resumes it. OK and Reject still act immediately while paused. For breaks under five minutes, it reopens the interrupted entry and includes the break. Otherwise a new entry starts at the return instant. Rejection or cancellation leaves the pending interval untracked.
