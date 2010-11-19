%%%-------------------------------------------------------------------
%%% File    : npers_spawner.erl
%%% Author  : Fredrik Thulin <ft@it.su.se>
%%% Descrip : The spawner is the process that starts n checks per
%%%           second.
%%%
%%% Created : 18 Nov 2010 by Fredrik Thulin <ft@it.su.se>
%%%-------------------------------------------------------------------
-module(npers_spawner).

-behaviour(gen_server).

%% API
-export([start_link/1,
	 info/0
	]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state, {interval_timer_ref :: timer:tref(),
		stats_timer_ref :: timer:tref(),
		interval_secs :: non_neg_integer(),
		checks_count :: non_neg_integer(),
		all_checks :: list(),
		start_checks :: list(),
		start_per_interval :: non_neg_integer(),
		workers_started = 0 :: non_neg_integer(),
		options :: []
	       }).

-define(SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Options) when is_list(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []).

info() ->
    gen_server:call(?SERVER, get_info).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init(Options) when is_list(Options) ->
    Interval = proplists:get_value(interval, Options, 300),

    {ok, TRef} = timer:send_interval(1000, wake_up),

    {ok, StatsTRef} = timer:send_interval(Interval * 1000, dump_stats),

    Checks = [],

    State1 = #state{interval_timer_ref = TRef,
		    stats_timer_ref = StatsTRef,
		    interval_secs = Interval,
		    options = Options
		   },
    State = set_checks(State1, Checks),

    io:format("Started npers_spawner - will fire ~p checks every ~p seconds.~n",
	      [State#state.start_per_interval, Interval]),

    {ok, State}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({set_checks, Checks}, _From, State) when is_list(Checks) ->
    NewState = set_checks (State, Checks),
    {reply, ok, NewState};

handle_call(get_info, _From, State) ->
    Info = [{interval_secs, State#state.interval_secs},
	    {checks_count, State#state.checks_count},
	    {all_checks_length, length(State#state.all_checks)},
	    {start_checks_length, length(State#state.start_checks)},
	    {start_per_interval, State#state.start_per_interval},
	    {started_this_interval, State#state.workers_started}
	    ],
    {reply, {ok, Info}, State};

handle_call(_Request, _From, State) ->
    Reply = not_implemented,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(wake_up, #state{start_per_interval = 0} = State) ->
    %% Ignore, we have not been told what checks to run
    {noreply, State};

handle_info(wake_up, State) ->
    NewState = start_checks(State),
    {noreply, NewState};

handle_info(dump_stats, State) ->
    io:format("~p : Started ~p checks the last ~p seconds~n",
	      [self(), State#state.workers_started, State#state.interval_secs]),
    {noreply, State#state{workers_started = 0}};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

start_checks(State) ->
    #state{start_per_interval = StartNum,
	   start_checks    = SChecks,
	   options         = Options,
	   workers_started = PreviouslyStarted
	  } = State,
    NewSChecks = start_checks2(StartNum, SChecks, State, Options),
    State#state{start_checks    = NewSChecks,
		workers_started = StartNum + PreviouslyStarted
	       }.

start_checks2(Count, [H | T], State, Options) when Count > 0 ->
    npers_worker:start(H, Options),
    start_checks2(Count - 1, T, State, Options);
start_checks2(Count, [], State, Options) ->
    %% restart with all the checks when Count reaches zero
    SChecks = State#state.all_checks,
    start_checks2(Count, SChecks, State, Options);
start_checks2(Count, SChecks, _State, _Options) when Count =:= 0 ->
    %% finished starting workers for this time
    SChecks.

set_checks(State, Checks) when is_list(Checks) ->
    Interval = State#state.interval_secs,
    NumChecks = length(Checks),
    State#state{
      all_checks = Checks,
      start_checks = Checks,
      checks_count = NumChecks,
      start_per_interval = NumChecks div Interval
     }.
