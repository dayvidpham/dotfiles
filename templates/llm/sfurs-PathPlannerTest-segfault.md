# Bug Report: PathPlannerTest Segfaults when Running Tests

## Description

### Steps to Reproduce

Trying to run this command results in the test runner segfaulting.

```
./build/test/unit_tests
```

Output logs
```
[     0.000][Info][Runner]{/home/minttea/dev/sfurs-software-nixified/software/816-DavidP-BallRecovery/test/runner/Runner.cpp:84}:Using alphabetical order

Running test "start equals goal (multi)"... FAILED
in: /home/minttea/dev/sfurs-software-nixified/software/816-DavidP-BallRecovery/test/pathplanning/TestPathPlanner.cpp:225 - test condition:  [false]

zsh: abort (core dumped)  ./build/test/unit_tests
```

## LLDB Debugger Output

### Relevant Stack Frames, Variables


```cpp
(lldb) fr s 7
frame #7: 0x0000555555978a34 unit_tests`QList<Cell>::last(this=0x0000555556683228) const at qlist.h:680:45
   677      inline const T &first() const noexcept { Q_ASSERT(!isEmpty()); return *begin(); }
   678      inline const T &constFirst() const noexcept { Q_ASSERT(!isEmpty()); return *begin(); }
   679      inline T& last() { Q_ASSERT(!isEmpty()); return *(end()-1); }
-> 680      inline const T &last() const noexcept { Q_ASSERT(!isEmpty()); return *(end()-1); }
   681      inline const T &constLast() const noexcept { Q_ASSERT(!isEmpty()); return *(end()-1); }
   682      inline bool startsWith(parameter_type t) const { return !isEmpty() && first() == t; }
   683      inline bool endsWith(parameter_type t) const { return !isEmpty() && last() == t; }
```

```cpp
(lldb) fr s 9
frame #9: 0x0000555555970fe0 unit_tests`$_0::operator(this=0x00007ffffffd0e27)() const::'lambda3'()::operator()() const at TestPathPlanner.cpp:226:22
   223              const auto& p = results[id];
   224              print_path(p, "start==goal", id);
   225              expect(!p.isEmpty());
-> 226              expect(p.back().x == goals[id].x && p.back().y == goals[id].y);
   227              for (int i = 1; i < p.size(); ++i)
   228                  expect(adjacent_or_same(grid, p[i-1], p[i])) << "steps must be neighbors or waits";
   229          }
```

Variables in Stack Frame 9 have these values:

```cpp
(lldb) frame variable
(const (unnamed class) *) this = 0x00007ffffffd0e27
(HexagonalGrid) grid = {
  evenColOffsets = {
    [0] = (first = 1, second = 0)
    [1] = (first = -1, second = 0)
    [2] = (first = 0, second = -1)
    [3] = (first = -1, second = -1)
    [4] = (first = 1, second = -1)
    [5] = (first = 0, second = 1)
  }
  oddColOffsets = {
    [0] = (first = 1, second = 0)
    [1] = (first = -1, second = 0)
    [2] = (first = 0, second = 1)
    [3] = (first = -1, second = 1)
    [4] = (first = 1, second = 1)
    [5] = (first = 0, second = -1)
  }
  grid = {
    d = {
      d = 0x0000555556681a90
      ptr = 0x0000555556681aa0
      size = 44
    }
  }
  blueRobotIdToOccupied = {
    d = 0x00005555566149e0
  }
  yellowRobotIdToOccupied = {
    d = nullptr
  }
  blueRobotIdToPosition = {
    d = 0x0000555556614b10
  }
  yellowRobotIdToPosition = {
    d = nullptr
  }
  fieldLength = 9000
  fieldWidth = 6000
  numColumns = 44
  numRows = 55
  originX = 5000
  originY = 3500
  hexSideLength = 103.92304845413263
  hexWidth = 207.84609690826525
  hexHeight = 179.99999999999997
  horizSpacing = 155.88457268119893
  vertSpacing = 179.99999999999997
  ROBOT_RADIUS = 90
  gridOOBMargin = 500
}
(const Team) team = BLUE
(const QSet<int>) ids = {
  q_hash = {
    d = 0x00005555567800e0
  }
}
(PathPlanner) planner = {
  grid = 0x00007ffffffd0d08
  robotIdToDStar = {
    d = 0x000055555672a820
  }
  robotIdToGoal = {
    d = 0x0000555556665840
  }
  robotIds = {
    q_hash = {
      d = 0x00005555567800e0
    }
  }
  friendlyTeam = BLUE
}
(QHash<int, Cell>) goals = {
  d = 0x00005555566657e0
}
(QHash<int, QList<Cell> >) results = {
  d = 0x0000555556665870
}
(int) id = 3
(const QList<Cell> &) p = 0x0000555556683228: {
  d = {
    d = nullptr
    ptr = nullptr
    size = 0
  }
}
```


```cpp
(lldb) fr s 10
frame #10: 0x0000555555970a8e unit_tests`$_0::operator()() const::'lambda3'()::__invoke() at TestPathPlanner.cpp:202:40
   199          expect(results.isEmpty()) << "planner should return empty map for empty goals";
   200      };
   201
-> 202      "start equals goal (multi)"_test = [] {
   203          auto grid = make_grid();
   204          const Team team = Team::BLUE;
   205          const QSet<int> ids{1,2,3};
```



### Stack Trace

```cpp
(lldb) bt
* thread #1, name = 'unit_tests', stop reason = signal SIGABRT
    frame #0: 0x00007ffff369984c libc.so.6`__pthread_kill_implementation + 284
    frame #1: 0x00007ffff3641406 libc.so.6`raise + 22
    frame #2: 0x00007ffff362893a libc.so.6`abort + 215
    frame #3: 0x00007ffff3ed4401 libQt6Core.so.6`qAbort() + 12
    frame #4: 0x00007ffff3f2a139 libQt6Core.so.6`qt_message(QtMsgType, QMessageLogContext const&, char const*, __va_list_tag*) + 297
    frame #5: 0x00007ffff3ed5a06 libQt6Core.so.6`QMessageLogger::fatal(char const*, ...) const + 252
  * frame #6: 0x00007ffff3ed445d libQt6Core.so.6`qt_assert(char const*, char const*, int) + 92
    frame #7: 0x0000555555978a34 unit_tests`QList<Cell>::last(this=0x0000555556683228) const at qlist.h:680:45
    frame #8: 0x0000555555971725 unit_tests`QList<Cell>::back(this=0x0000555556683228) const at qlist.h:721:59
    frame #9: 0x0000555555970fe0 unit_tests`$_0::operator(this=0x00007ffffffd0e27)() const::'lambda3'()::operator()() const at TestPathPlanner.cpp:226:22
    frame #10: 0x0000555555970a8e unit_tests`$_0::operator()() const::'lambda3'()::__invoke() at TestPathPlanner.cpp:202:40
    frame #11: 0x00005555556e4f63 unit_tests`boost::ext::ut::v2_3_1::events::test<void (*)(), boost::ext::ut::v2_3_1::none>::run_impl(test=(unit_tests`$_0::operator()() const::'lambda3'()::__invoke() at TestPathPlanner.cpp:202), (null)=0x00007ffffffd1178) at ut.hpp:582:60
    frame #12: 0x00005555556e4ead unit_tests`boost::ext::ut::v2_3_1::events::test<void (*)(), boost::ext::ut::v2_3_1::none>::operator()(this=0x00007ffffffd1128) at ut.hpp:578:33
    frame #13: 0x00005555556e4ae9 unit_tests`auto boost::ext::ut::v2_3_1::runner<boost::ext::ut::v2_3_1::reporter_junit<boost::ext::ut::v2_3_1::printer>, 16>::on<void (*)(), boost::ext::ut::v2_3_1::none>(this=0x00005555560920f0, test=test<void (*)(), boost::ext::ut::v2_3_1::none> @ 0x00007ffffffd1128) at ut.hpp:2131:9
    frame #14: 0x00005555556e42a3 unit_tests`decltype(auto) boost::ext::ut::v2_3_1::detail::on<boost::ext::ut::v2_3_1::events::test<void (*)(), boost::ext::ut::v2_3_1::none>>(event=0x00007ffffffd1210) at ut.hpp:2256:73
    frame #15: 0x00005555556e24cd unit_tests`auto boost::ext::ut::v2_3_1::detail::test::operator=<>(this=0x00007ffffffd12e0, _test=test_location<void (*)()> @ 0x00007ffffffd1200) at ut.hpp:2279:5
    frame #16: 0x000055555596e252 unit_tests`$_0::operator()(this=0x00007ffffffd14b7) const at TestPathPlanner.cpp:202:38
    frame #17: 0x000055555596e00e unit_tests`$_0::__invoke() at TestPathPlanner.cpp:87:63
    frame #18: 0x000055555585a8b0 unit_tests`cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0::operator()(this=0x0000555556174a50) const at Runner.cpp:125:13
    frame #19: 0x000055555585a528 unit_tests`QtPrivate::FunctorCall<std::integer_sequence<unsigned long>, QtPrivate::List<>, void, cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0>::call(this=0x00007ffffffd1820)::$_0&, void**)::'lambda'()::operator()() const at qobjectdefs_impl.h:116:24
    frame #20: 0x000055555585a4f9 unit_tests`void QtPrivate::FunctorCallBase::call_internal<void, QtPrivate::FunctorCall<std::integer_sequence<unsigned long>, QtPrivate::List<>, void, cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0>::call(cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0&, void**)::'lambda'()>(args=0x00007ffffffd1958, fn=0x00007ffffffd1820) at qobjectdefs_impl.h:65:17
    frame #21: 0x000055555585a4b2 unit_tests`QtPrivate::FunctorCall<std::integer_sequence<unsigned long>, QtPrivate::List<>, void, cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0>::call(f=0x0000555556174a50, arg=0x00007ffffffd1958) at qobjectdefs_impl.h:115:13
    frame #22: 0x000055555585a441 unit_tests`void QtPrivate::FunctorCallable<cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0>::call<QtPrivate::List<>, void>(f=0x0000555556174a50, (null)=0x0000555556172b70, arg=0x00007ffffffd1958) at qobjectdefs_impl.h:337:13
    frame #23: 0x000055555585a388 unit_tests`QtPrivate::QCallableObject<cfgs::Runner::run_suites(QCoreApplication*, cfgs::RunnerConfig)::$_0, QtPrivate::List<>, void>::impl(which=1, this_=0x0000555556174a40, r=0x0000555556172b70, a=0x00007ffffffd1958, ret=0x0000000000000000) at qobjectdefs_impl.h:547:21
    frame #24: 0x00007ffff40218a0 libQt6Core.so.6`void doActivate<false>(QObject*, int, void**) + 1760
    frame #25: 0x00007ffff402fbef libQt6Core.so.6`QSingleShotTimer::timerEvent(QTimerEvent*) + 159
    frame #26: 0x00007ffff4012c15 libQt6Core.so.6`QObject::event(QEvent*) + 245
    frame #27: 0x00007ffff3fb59dd libQt6Core.so.6`QCoreApplication::notifyInternal2(QObject*, QEvent*) + 269
    frame #28: 0x00007ffff41893ef libQt6Core.so.6`QTimerInfoList::activateTimers() + 1599
    frame #29: 0x00007ffff42d2e5c libQt6Core.so.6`timerSourceDispatch(_GSource*, int (*)(void*), void*) + 44
    frame #30: 0x00007ffff55018de libglib-2.0.so.0`g_main_context_dispatch_unlocked + 462
    frame #31: 0x00007ffff5503b50 libglib-2.0.so.0`g_main_context_iterate_unlocked.isra.0 + 752
    frame #32: 0x00007ffff550437c libglib-2.0.so.0`g_main_context_iteration + 44
    frame #33: 0x00007ffff42d3063 libQt6Core.so.6`QEventDispatcherGlib::processEvents(QFlags<QEventLoop::ProcessEventsFlag>) + 115
    frame #34: 0x00007ffff3fc440b libQt6Core.so.6`QEventLoop::exec(QFlags<QEventLoop::ProcessEventsFlag>) + 443
    frame #35: 0x00007ffff3fbf6be libQt6Core.so.6`QCoreApplication::exec() + 174
    frame #36: 0x00005555558586b3 unit_tests`cfgs::Runner::run_suites(this=0x00005555560920f0, app=0x00007ffffffd2208, cfg=cfgs::RunnerConfig @ 0x00007ffffffd2228) at Runner.cpp:136:5
    frame #37: 0x00005555558584c3 unit_tests`cfgs::Runner::start_runner(this=0x00005555560920f0, cfg=cfgs::RunnerConfig @ 0x00007ffffffd3818) at Runner.cpp:101:5
    frame #38: 0x000055555567de9a unit_tests`cfgs::Runner::run(this=0x00005555560920f0, cfg=cfgs::RunnerConfig @ 0x00007ffffffd4e58) at Runner.h:19:20
    frame #39: 0x000055555567c87e unit_tests`main(argc=1, argv=0x00007ffffffd5568) at main.cpp:124:34
    frame #40: 0x00007ffff362a47e libc.so.6`__libc_start_call_main + 126
    frame #41: 0x00007ffff362a539 libc.so.6`__libc_start_main@@GLIBC_2.34 + 137
    frame #42: 0x0000555555612635 unit_tests`_start + 37
```



