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
The configurable opportunity to reject resuming a task after returning from screen lock or sleep. Clicking OK or opening DayTape accepts it immediately. Clicking elsewhere or using other apps keeps its popup visible until the countdown finishes or Reject is clicked. General → Tracking sets the countdown from 1 to 60 seconds, defaulting to nine seconds. Changes apply to the next offer. Hovering over the notice freezes the remaining countdown; moving away resumes it. OK and Reject still act immediately while paused. Automatic resume is on by default; disabling it cancels the offer and leaves tracking stopped after returning. For breaks shorter than the configured threshold, it reopens the interrupted entry and includes the break. The threshold defaults to five minutes and ranges from zero to 60 minutes; zero means never include breaks. At or above the threshold, a new entry starts at the return instant. The threshold is fixed when each offer begins. Rejection or cancellation leaves the pending interval untracked.
