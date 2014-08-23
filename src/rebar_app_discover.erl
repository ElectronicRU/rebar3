-module(rebar_app_discover).

-export([do/2,
         find_unbuilt_apps/1,
         find_apps/1,
         find_apps/2]).

do(State, LibDirs) ->
    Apps = find_apps(LibDirs, all),
    lists:foldl(fun(AppInfo, StateAcc) ->
                        rebar_state:apps_to_build(StateAcc, AppInfo)
            end, State, Apps).

-spec all_app_dirs(list(file:name())) -> list(file:name()).
all_app_dirs(LibDirs) ->
    lists:flatmap(fun(LibDir) ->
                          app_dirs(LibDir)
                  end, LibDirs).

app_dirs(LibDir) ->
    Path1 = filename:join([LibDir,
                           "*",
                           "src",
                           "*.app.src"]),
    Path2 = filename:join([LibDir,
                           "src",
                           "*.app.src"]),

    Path3 = filename:join([LibDir,
                           "*",
                           "ebin",
                           "*.app"]),
    Path4 = filename:join([LibDir,
                           "ebin",
                           "*.app"]),

    lists:usort(lists:foldl(fun(Path, Acc) ->
                                    Files = filelib:wildcard(to_list(Path)),
                                    [app_dir(File) || File <- Files] ++ Acc
                            end, [], [Path1, Path2, Path3, Path4])).

to_list(S) when is_list(S) ->
    S;
to_list(S) when is_binary(S) ->
    binary_to_list(S).

find_unbuilt_apps(LibDirs) ->
    find_apps(LibDirs, invalid).

find_apps(LibDirs) ->
    find_apps(LibDirs, valid).

find_apps(LibDirs, Validate) ->
    lists:filtermap(fun(AppDir) ->
                      AppFile = filelib:wildcard(filename:join([AppDir, "ebin", "*.app"])),
                      AppSrcFile = filelib:wildcard(filename:join([AppDir, "src", "*.app.src"])),
                      case AppFile of
                          [File] ->
                              AppInfo = create_app_info(AppDir, File),
                              AppInfo1 = rebar_app_info:app_file(AppInfo, File),
                              AppInfo2 = case AppSrcFile of
                                             [F] ->
                                                 rebar_app_info:app_file_src(AppInfo1, F);
                                             [] ->
                                                 AppInfo1
                                         end,
                              case Validate of
                                  valid ->
                                      case validate_application_info(AppInfo2) of
                                          true ->
                                              {true, AppInfo2};
                                          false ->
                                              false
                                      end;
                                  invalid ->
                                      case validate_application_info(AppInfo2) of
                                          false ->
                                              {true, AppInfo2};
                                          true ->
                                              false
                                      end;
                                  all ->
                                      {true, AppInfo2}
                              end;
                          [] ->
                              case AppSrcFile of
                                  [File] ->
                                      case Validate of
                                          V when V =:= invalid ; V =:= all ->
                                              AppInfo = create_app_info(AppDir, File),
                                              {true, rebar_app_info:app_file_src(AppInfo, File)};
                                          valid ->
                                              false
                                      end;
                                  [] ->
                                      false
                              end
                      end
              end, all_app_dirs(LibDirs)).

app_dir(AppFile) ->
    filename:join(lists:droplast(filename:split(filename:dirname(AppFile)))).

create_app_info(AppDir, AppFile) ->
    case file:consult(AppFile) of
        {ok, [{application, AppName, AppDetails}]} ->
            AppVsn = proplists:get_value(vsn, AppDetails),
            AbsCwd = filename:absname(rebar_utils:get_cwd()),
            {ok, AppInfo} = rebar_app_info:new(AppName, AppVsn, AppDir),
            RebarConfig = filename:join(AppDir, "rebar.config"),
            AppState = case filelib:is_file(RebarConfig) of
                            true ->
                                Terms = rebar_config:consult_file(RebarConfig),
                                rebar_state:new(Terms);
                            false ->
                                rebar_state:new()
                        end,
            AppState1 = rebar_state:set(AppState, base_dir, AbsCwd),
            AppInfo1 = rebar_app_info:config(
                         rebar_app_info:app_details(AppInfo, AppDetails), AppState1),
            rebar_app_info:dir(AppInfo1, AppDir)
    end.

-spec validate_application_info(rebar_app_info:t()) -> boolean().
validate_application_info(AppInfo) ->
    EbinDir = rebar_app_info:ebin_dir(AppInfo),
    AppFile = rebar_app_info:app_file(AppInfo),
    AppDetail = rebar_app_info:app_details(AppInfo),
    case get_modules_list(AppFile, AppDetail) of
        {ok, List} ->
            has_all_beams(EbinDir, List);
        _Error ->
            false
    end.

-spec get_modules_list(file:name(), proplists:proplist()) ->
                              {ok, list()} |
                              {warning, Reason::term()} |
                              {error, Reason::term()}.
get_modules_list(AppFile, AppDetail) ->
    case proplists:get_value(modules, AppDetail) of
        undefined ->
            {warning, {invalid_app_file, AppFile}};
        ModulesList ->
            {ok, ModulesList}
    end.

-spec has_all_beams(file:name(), list()) ->
                           ok | {error, Reason::term()}.
has_all_beams(EbinDir, [Module | ModuleList]) ->
    BeamFile = filename:join([EbinDir,
                              list_to_binary(atom_to_list(Module) ++ ".beam")]),
    case filelib:is_file(BeamFile) of
        true ->
            has_all_beams(EbinDir, ModuleList);
        false ->
            false
    end;
has_all_beams(_, []) ->
    true.