-module(test).

-compile(export_all).

-include("fsm.hrl").

%%-record(transition, {
%%    current_state         :: state(),
%%    event                 :: event(),
%%    to_state              :: state(),
%%    pre_listerners        :: pre_listerners(),
%%    post_listerners       :: post_listerners()
%%  }). 

run() ->
  {ok, _} = application:ensure_all_started(fsm),
  TA = [
    #transition{
      event = 'e1',
      to_state = 'b',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    },
    #transition{
      event = 'e2',
      to_state = 'c',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    }],
  StateA = #state_entry{
    state = 'a',
    transitions = TA
  },

  TB = [
    #transition{
      event = 'e3',
      to_state = 'd',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    }],
  StateB = #state_entry{
    state = 'b',
    transitions = TB
  },

  TC = [
    #transition{
      event = 'e4',
      to_state = 'e',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    },
    #transition{
      event = 'e5',
      to_state = 'b',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    }],
  StateC = #state_entry{
    state = 'c',
    transitions = TC
  },

  StateD = #state_entry{
    state = 'd',
    transitions = []
  },

  StateE = #state_entry{
    state = 'e',
    transitions = []
  },

  TB1 =
    #transition{
      event = 'e6',
      to_state = 'f',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    },

  TF =
    #transition{
      event = 'e7',
      to_state = 'b',
      pre_listerners = [{test, a2b1, []}],
      post_listerners = [{test, a2b2, []}]
    },

  {ok, Machine} = fsm:start_link(test, [StateA, StateB, StateC, StateD, StateE]),

    %% a => b => d
%%  fsm:transition(Machine, 'e1', " a => b "),
%%  fsm:transition(Machine, 'e3', " b => d "),
%%  fsm:transition(Machine, 'e4', " d => n "),

    %% a => c => e
  fsm:transition(Machine, 'e2', " a => c "),
  fsm:transition(Machine, 'e5', " c => b "),

  fsm:add_transition(Machine, 'b', TB1),
  fsm:add_transition(Machine, 'f', TF),

  CurrState = fsm:get_current_state(Machine),
  lager:debug("(test) get current_state:~p", [CurrState]),

  NextState = fsm:get_next_state(Machine, 'e6'),
  lager:debug("(test) get get_next_state:~p", [NextState]),

  FromStates = fsm:get_from_states(Machine),
  lager:debug("(test) get get_from_states:~p", [FromStates]),

  IsOver1 = fsm:is_over(Machine),
  lager:debug("(test1---------------------) get is_over:~p", [IsOver1]),

  fsm:transition(Machine, 'e6', " b => f "),
  fsm:transition(Machine, 'e7', " f => b "),
  fsm:transition(Machine, 'e3', " b => d "),
  fsm:transition(Machine, 'e',  " d => n "),

  IsOver = fsm:is_over(Machine),
  lager:debug("(test2---------------------) get is_over:~p", [IsOver]),

  ok.

a2b1(A, Args, CurrentState, Event, NextState, Context) ->
  lager:debug("(test) machine pre :~p ====(event:~p)======> ~p", [CurrentState, Event, NextState]),
  Context.

a2b2(A, Args, CurrentState, Event, NextState, Context) ->
  lager:debug("(test) post machine "),
  Context.


