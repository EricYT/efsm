-module(fsm).
-behaviour(gen_server).

-include("fsm.hrl").


-type state_entry()   :: #state_entry{}.
-type state_entries() :: [state_entry(), ...].


-record(state, {
    name          :: atom(),
    current_state :: state(),
    state_entries :: state_entries(),
    context       :: map(),
    is_over       :: boolean()
}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/2]).
-compile(export_all).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
    terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(StateMachineName, StateEntries) ->
  gen_server:start_link({local, StateMachineName}, ?MODULE, [StateMachineName, StateEntries], []).

transition(StateMachine, Event, Args) ->
  gen_server:call(StateMachine, {transition, Event, Args}).

add_transition(StateMachine, StateName, Transition) ->
  gen_server:call(StateMachine, {add_transition, StateName, Transition}).

del_transition(StateMachine, StateName) ->
  gen_server:call(StateMachine, {del_transition, StateName}).

is_over(StateMachine) ->
  gen_server:call(StateMachine, {is_over}).

get_current_state(StateMachine) ->
  gen_server:call(StateMachine, {get_current_state}).

get_next_state(StateMachine, Event) ->
  gen_server:call(StateMachine, {get_next_state, Event}).

get_from_states(StateMachine) ->
  gen_server:call(StateMachine, {get_from_states}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([StateMachineName, StateEntries]) ->
  %% Initialize the state machine
  [StartState] = get_start_state(StateEntries),
  lager:debug("(1)Machine: ~p all_states:~p StartState:~p", [StateMachineName, get_all_states(StateEntries, []), StartState]),
  State = #state{
    name          = StateMachineName,
    current_state = StartState,
    state_entries = StateEntries,
    context       = maps:new()
  },
  {ok, State}.

handle_call({transition, Event, Args}, _From, State) ->
  lager:debug("(start)transition event:~p args:~p ", [Event, Args]),
  {Reply, NewState} = transition_to(Event, Args, State),
  lager:debug("(end)transition event end reply:~p", [Reply]),
  {reply, Reply, NewState};

handle_call({add_transition, StateName, Transitions}, _From, State) ->
  lager:debug("(add_transition) add state:~p", [StateName]),
  {Reply, NewState} = add_transition_(StateName, Transitions, State),
  {reply, Reply, NewState};

handle_call({del_transition, StateName, Event}, _From, State) ->
  lager:debug("(add_transition) add state:~p", [{StateName, Event}]),
  {Reply, NewState} = del_transition_(StateName, Event, State),
  {reply, Reply, NewState};

handle_call({get_current_state}, _From, State) ->
  #state{ current_state=CurrentState } = State,
  {reply, {ok, CurrentState}, State};

handle_call({get_next_state, Event}, _From, State) ->
  Reply = get_next_state_(Event, State),
  {reply, Reply, State};

handle_call({is_over}, _From, State) ->
  Reply = is_over_(State),
  {reply, Reply, State};

handle_call({get_from_states}, _From, State) ->
  Reply = get_from_states_(State),
  {reply, Reply, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
%%-record(transition, {
%%    event                 :: event(),
%%    to_state              :: state(),
%%    pre_listerners        :: pre_listerners(),
%%    post_listerners       :: post_listerners()
%%  }). 
-spec transition_to(event(), Args::[any(), ...], State::tuple()) -> {{ok, true}|{error, Reason::any()}, NewState::tuple()}.
transition_to(Event, Args, State) ->
  lager:debug("(3)transition_to in"),
  #state{
    current_state=CurrentState,
    state_entries=StateEntries,
    context      =Context
  }=State,
  {Result, NewState, NewContext1} =
  case get_next_state(CurrentState, Event, StateEntries) of
    #transition{
      to_state       = NextState,
      pre_listerners = PreListerners,
      post_listerners= PostListerners
    }=_Transition ->
      lager:debug("(4)transition_to get next state:~p", [NextState]),
      {ok, NewContext} = do_pre_listerners(PreListerners, CurrentState, Event, NextState, Args, Context),
      case maybe_over(NextState, StateEntries) of
        true  ->
          lager:debug("(5)state machine is over"),
          {{ok, true}, NextState, NewContext};
        false ->
          lager:debug("(6)state machine is not over"),
          NewContext_ = do_post_listerners(PostListerners, CurrentState, Event, NextState, Args, NewContext),
          {{ok, true}, NextState, NewContext_}
      end;
    undefined ->
      {{error, event_error}, CurrentState, Context}
  end,
  {Result, State#state{ current_state=NewState, context=NewContext1 }}.

add_transition_(StateName, Transition, State) ->
  lager:debug("(add_transition)in"),
  #state{
    state_entries=StateEntries
  }=State,
  {Result, NewStateEntries} =
  case get_state_entry(StateName, StateEntries) of
    undefined ->
      StateEntry = make_state_entry(StateName, Transition),
      {{ok, true}, [StateEntry|StateEntries] };
    #state_entry{ transitions=OriTranistions }=StateEntry ->
      #transition{ event=Event } = Transition,
      case get_transition(Event, OriTranistions) of
        undefined ->
          NewTransitions = [Transition|OriTranistions],
          NewStateEntries_ = lists:keyreplace(StateName, #state_entry.state, StateEntries, StateEntry#state_entry{ transitions=NewTransitions }),
          {{ok, true}, NewStateEntries_};
        _     ->
          {{error, already_exists}, StateEntries}
      end
  end,
  {Result, State#state{ state_entries=NewStateEntries }}.

make_state_entry(StateName, Transition) ->
  #state_entry{ state = StateName, transitions = [Transition] }.

del_transition_(StateName, Event, State) ->
  lager:debug("(del_transition)in"),
  #state{
    state_entries=StateEntries
  }=State,
  {Result, NewStateEntries} =
  case get_state_entry(StateName, StateEntries) of
    undefined ->
      {{error, not_exists}, StateEntries};
    #state_entry{ transitions=OriTranistions }=StateEntry ->
      NewTransitions = lists:keydelete(Event, #transition.event, OriTranistions),
      NewStateEntries_ = lists:keyreplace(StateName, #state_entry.state, StateEntries, StateEntry#state_entry{ transitions=NewTransitions }),
      {{ok, true}, NewStateEntries_}
  end,
  {Result, State#state{ state_entries=NewStateEntries }}.

get_next_state_(Event, State) ->
  #state{
    current_state=CurrentState,
    state_entries=StateEntries
  }=State,
  case get_next_state(CurrentState, Event, StateEntries) of
    #transition{
      to_state       = NextState
    }=_Transition ->
      {ok, NextState};
    _             ->
      {ok, []}
  end.

get_from_states_(State) ->
  #state{
    current_state=CurrentState,
    state_entries=StateEntries
  }=State,
  {ok, get_from_states(StateEntries, CurrentState, [])}.

get_from_states([#state_entry{ state=State, transitions=Transitions }|Tail], CurrState, Acc) ->
  case lists:keyfind(CurrState, #transition.to_state, Transitions) of
    false ->
      get_from_states(Tail, CurrState, Acc);
    _     ->
      get_from_states(Tail, CurrState, [State|Acc])
  end;
get_from_states([], _, Acc) -> Acc.

get_next_state(CurrentState, Event, StateEntries) ->
  case get_state_entry(CurrentState, StateEntries) of
    undefined ->
      undefined;
    #state_entry{ transitions=Transitions } ->
      get_transition(Event, Transitions)
  end.

maybe_over(State, StateEntries) ->
  case get_state_entry(State, StateEntries) of
    #state_entry{ transitions=[] } -> true;
    #state_entry{}                 -> false;
    _                              ->
      lager:error("transition_to error state_entry:~p", [{State, StateEntries}]),
      true
  end.

do_pre_listerners([{M, F, A}|Tail], CurrentState, Event, NextState, Args, Context) ->
  case erlang:function_exported(M, F, 6) of
    true ->
      NewContext = M:F(A, Args, CurrentState, Event, NextState, Context),
      do_pre_listerners(Tail, CurrentState, Event, NextState, Args, NewContext);
    false ->
      do_pre_listerners(Tail, CurrentState, Event, NextState, Args, Context)
  end;
do_pre_listerners([], _, _, _, _, Context) -> {ok, Context}.

do_post_listerners([{M, F, A}|Tail], CurrentState, Event, NextState, Args, Context) ->
  case erlang:function_exported(M, F, 6) of
    true ->
      NewContext = M:F(A, Args, CurrentState, Event, NextState, Context),
      do_post_listerners(Tail, CurrentState, Event, NextState, Args, NewContext);
    false ->
      do_post_listerners(Tail, CurrentState, Event, NextState, Args, Context)
  end;
do_post_listerners([], _, _, _, _, Context) -> {ok, Context}.

get_start_state(StateEntries) ->
  AllStates      = get_all_states(StateEntries, []),
  AllTransitions = get_all_transitions(StateEntries, []),
  filter_start_state(AllStates, AllTransitions, []).

get_all_states([#state_entry{ state=State }|Tail], Acc) ->
  get_all_states(Tail, [State|Acc]);
get_all_states([], Acc) -> Acc.

get_all_transitions([#state_entry{ transitions=Transitions }|Tail], Acc) ->
  get_all_transitions(Tail, Transitions++Acc);
get_all_transitions([], Acc) -> Acc.

filter_start_state([State|Tail], AllTransitions, Acc) ->
  case lists:keyfind(State, #transition.to_state, AllTransitions) of
    false ->
      filter_start_state(Tail, AllTransitions, [State|Acc]);
    _     ->
      filter_start_state(Tail, AllTransitions, Acc)
  end;
filter_start_state([], _, Acc) -> Acc.
      
get_state_entry(State, StateEntries) ->
  case lists:keyfind(State, #state_entry.state, StateEntries) of
    false      -> undefined;
    StateEntry -> StateEntry
  end.

get_transition(Event, Transitions) ->
  case lists:keyfind(Event, #transition.event, Transitions) of
    false      -> undefined;
    Transition -> Transition
  end.

is_over_(#state{current_state=CurrentState, state_entries=StateEntries}) ->
  case get_state_entry(CurrentState, StateEntries) of
    undefined -> true;
    #state_entry{transitions=[]} -> true;
    _ -> false
  end.
