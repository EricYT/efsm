%% Types define
-type state() :: atom().
-type event() :: atom().
-type listerner() :: mfa().
-type pre_listerners() :: [listerner(), ...].
-type post_listerners() :: [listerner(), ...].
-type transition() :: tuple().
-type transitions() :: [transition(), ...].


%% Fsm entry
-record(state_entry, {
    state                 :: state(),
    transitions           :: transitions()
  }).

%% Fsm Transition
-record(transition, {
    event                 :: event(),
    to_state              :: state(),
    pre_listerners        :: pre_listerners(),
    post_listerners       :: post_listerners()
  }).
