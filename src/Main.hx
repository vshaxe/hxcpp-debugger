import js.Promise;
import protocol.debug.Types;
import js.node.Buffer;
import js.node.Net;
import js.node.ChildProcess;
import adapter.DebugSession;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.net.Socket;
import js.node.stream.Readable.ReadableEvent;
import adapter.DebugSession.Scope as ScopeImpl;
import debugger.IController;

typedef HxcppLaunchRequestArguments = {
	>protocol.debug.Types.LaunchRequestArguments,
	var program:String;
}

class Main extends adapter.DebugSession {

    static inline var port:Int = 6972;

    var connection:Connection;
	var debuggerState:DebuggerState;
	var stdOutBuffer:String;

	public function new() {
		debuggerState = new DebuggerState();
		super();
	}

    function traceToOutput(value:Dynamic, ?infos:haxe.PosInfos) {
        var msg = value;
        if (infos != null && infos.customParams != null) {
            msg += " " + infos.customParams.join(" ");
        }
        msg += "\n";
        sendEvent(new adapter.DebugSession.OutputEvent(msg));
    }

    override function initializeRequest(response:InitializeResponse, args:InitializeRequestArguments) {
        haxe.Log.trace = traceToOutput;
		response.body.supportsSetVariable = true;
		response.body.supportsConfigurationDoneRequest = true;
        sendResponse(response);
	}

    override function launchRequest(response:LaunchResponse, args:LaunchRequestArguments) {
		var args:HxcppLaunchRequestArguments = cast args;
		var program:String = args.program;

		function onStdout(data) {
			stdOutBuffer += data;
			var ind = stdOutBuffer.lastIndexOf("\n");
			if (ind >= 0) {
				var send = stdOutBuffer.substr(0, ind);
				var lines = send.split("\n");
				for (line in lines) {
					if (line != "") {
						sendEvent(new OutputEvent('[trace]> $line \n', OutputEventCategory.console));
					}
				}
				stdOutBuffer = stdOutBuffer.substr(ind);
			}
		}

		function onStderr(data) {
			trace('onStderr: $data');
		}

		function onConnected(socket:Socket) {
			trace("Remote debug connected!");
			socket.on(SocketEvent.Error, function(error) trace('Socket error: $error'));
            Connection.create(socket)
                .then(function(connection) {
                    this.connection = connection;
					debuggerState.initializing = true;
					connection.start();
				})
				.then(function(_) {
					return connection.sendCommand(Files);
				})
				.then(function(message:Message) {
					switch (message) {
						case Files(list):
							debuggerState.setWorkspaceFiles(list);
						default:
							trace('UNEXPECTED MESSAGE: $message');
					}
					return connection.sendCommand(FilesFullPath);
				}).then(function(message:Message) {
					switch (message) {
						case Files(list):
							debuggerState.setAbsFiles(list);
							debuggerState.calcPathDictionaries();
						default:
							trace('UNEXPECTED MESSAGE: $message');
					}
				})
				.then(function(_) {
					sendResponse(response);
					sendEvent(new adapter.DebugSession.InitializedEvent());
					debuggerState.initializing = false;
					return updateThreadStatus();
				})
				.then(function(_) {
					connection.on(Connection.INFO_MESSAGE, onInfoMessage);
				});
		}

		function onExit(_, _) {
			sendEvent(new adapter.DebugSession.TerminatedEvent(false));
		}

		var server = Net.createServer(onConnected);
		server.listen(port, function() {
			var args = [];
			var targetProcess = ChildProcess.spawn(program, args, {stdio: Pipe});
			targetProcess.stdout.on(ReadableEvent.Data, onStdout);
			targetProcess.stderr.on(ReadableEvent.Data, onStderr);
			targetProcess.on(ChildProcessEvent.Exit, onExit);
		});
	}

	override function configurationDoneRequest(response:ConfigurationDoneResponse, args:ConfigurationDoneArguments):Void {
		trace("configurationDoneRequest");
		connection.sendCommand(Continue(1))
			.then(function(message:Message) {
				trace('continue result: $message');
				sendResponse(response);
			});
	}

	override function continueRequest(response:ContinueResponse, args:ContinueArguments):Void {
		maybeSetCurrentThread(args.threadId)
			.then(function(message) {
				return connection.sendCommand(Continue(1));
			})
			.then(function(message:Message) {
				switch (message) {
					case OK:
						sendResponse(response);

					case ErrorBadCount(count):
						trace("ErrorBadCount");
						
					default:
						trace('UNEXPECTED MESSAGE: $message');
				}
			});
	}

	override function setBreakPointsRequest(response:SetBreakpointsResponse, args:SetBreakpointsArguments):Void {
		trace('args1: ${haxe.Json.stringify(args)}');

		var breakpoints = debuggerState.getBreakpointsByPath(args.source.path);
		var alreadySet = [for (b in breakpoints) b.line => b];
		var toRemove = [for (b in breakpoints) b];
		var newBreakpoints = [];
		response.body = {
			breakpoints:newBreakpoints
		};

		for (bs in args.breakpoints) {
			if (alreadySet.exists(bs.line)) {
				toRemove.remove(alreadySet[bs.line]);
				continue;
			}

			var b = new Breakpoint(true, bs.line, bs.column, cast args.source);
			newBreakpoints.push(b);
		}

		var last:Promise<debugger.IController.Message> = null;
		for (b in newBreakpoints) {
			var line = b.line;
			var workspacePath = debuggerState.absToWorkspace[args.source.path];
			last = connection.sendCommand(AddFileLineBreakpoint(workspacePath, line))
				.then(function(message) {
					
					trace(message);
					switch (message) {
						case FileLineBreakpointNumber(id):
							b.id = id;
						case ErrorNoSuchFile(fileName):
							response.success = false;
							response.message = 'no suche file:$fileName';
						
						default:
							'UNEXPECTED:$message';
					}
					return Promise.resolve(message);
				});
		}

		for (b in toRemove) {
			var workspacePath = debuggerState.absToWorkspace[args.source.path];
			last = connection.sendCommand(DeleteFileLineBreakpoint(workspacePath, b.line))
				.then(function(message) {
					switch (message) {
						case BreakpointStatuses(_):
							

						default:
							'UNEXPECTED:$message';
					}
					return Promise.resolve(message);
				});
		}

		last.then(function(_) {
			debuggerState.setBreakpointsByPath(args.source.path, cast newBreakpoints);
			trace(haxe.Json.stringify(response));
			sendResponse(response);
		});
	}

	override function scopesRequest(response:ScopesResponse, args:ScopesArguments):Void {
		trace('scopes');
		trace('args1: ${haxe.Json.stringify(args)}');

		var currentThreadNum:Int = debuggerState.currentThread;
		var handles = debuggerState.threads[currentThreadNum].handles;

		maybeSetFrame(args.frameId)
			.then(function(_) {
				var scopes:Array<Scope> = [
            		new ScopeImpl("Variables", handles.create(LocalsScope(args.frameId, new Map())), false)
				];

				response.body = {
					scopes: cast scopes
				};
				sendResponse(response);
			});
	}

	override function variablesRequest(response:VariablesResponse, args:VariablesArguments):Void {
		trace('variables');
		trace('args1: ${haxe.Json.stringify(args)}');

		var ref = debuggerState.getHandles().get(args.variablesReference);
		var vars = new Map<String, Variable>();
		response.body = {
			variables:[]
		};
		switch (ref) {
			case LocalsScope(frameId, variables):
				connection.sendCommand(Variables(false))
					.then(function(message) {
						var names = switch (message) {
							case debugger.Message.Variables(list):
								list;
							default:
								trace('UNEXPECTED: $message');
								[];
						}
						return Promise.resolve(names);
					})
					.then(function(varNames:Array<String>) {
						var last = Promise.resolve(0);
						for (varName in varNames) {
							last = connection.sendCommand(GetStructured(false, varName))
								.then(function(message) {
									switch (message) {
										case Structured(value):
											trace('$value');
											//response.body.variables.push(cast new Variable(expression, value));
										default:
											trace('UNEXPECTED: $message');
									}
									return Promise.resolve(0);
								});
						}
						return last;
					})
					.then(function(_) {
						sendResponse(response);
					});
		}
	}

	override function stackTraceRequest(response:StackTraceResponse, args:StackTraceArguments):Void {
		trace('stackTraceRequest');
		trace('args1: ${haxe.Json.stringify(args)}');
		var threadStatus = debuggerState.threads[args.threadId];
		response.body = {
			totalFrames:threadStatus.where.length,
			stackFrames:cast threadStatus.where
		};
		sendResponse(response);
	}

	override function threadsRequest(response:ThreadsResponse):Void {
		trace('threadsRequest');
		updateThreadStatus()
			.then(function(_) {
				var threads = debuggerState.threads;
				response.body = {
					threads:[]
				};
				for (t in threads) {
					response.body.threads.push(new Thread(t.id, t.name));
				}
				trace('threads response');
				sendResponse(response);
			});
	}

	override function stepInRequest(response:StepInResponse, args:StepInArguments) {
		trace('stepInRequest: ${haxe.Json.stringify(args)}');
		maybeSetCurrentThread(args.threadId)
			.then(function(_) {
				return connection.sendCommand(Step(1));
			})
			.then(function(message) {
				sendResponse(response);
			});
	}

	override function nextRequest(response:NextResponse, args:NextArguments) {
		trace('stepOutRequest: ${haxe.Json.stringify(args)}');
		maybeSetCurrentThread(args.threadId)
			.then(function(_) {
				return connection.sendCommand(Next(1));
			})
			.then(function(message) {
				sendResponse(response);
			});
	}

	override function stepOutRequest(response:StepOutResponse, args:StepOutArguments) {
		trace('stepOutRequest: ${haxe.Json.stringify(args)}');
		maybeSetCurrentThread(args.threadId)
			.then(function(_) {
				return connection.sendCommand(Finish(1));
			})
			.then(function(message) {
				sendResponse(response);
			});
	}

	function maybeSetFrame(id):Promise<Int> {
		var thread = debuggerState.threads[debuggerState.currentThread];
		return 
			if (thread.currentFrame != id) {
				connection.sendCommand(SetFrame(id))
					.then(function(message){
						thread.currentFrame = id;
						return Promise.resolve(id);
					});
			}
			else {
				Promise.resolve(id);
			}
	}

	function maybeSetCurrentThread(id):Promise<Int> {
		return 
			if (debuggerState.currentThread != id) {
				connection.sendCommand(SetCurrentThread(id))
					.then(function(message){
						debuggerState.currentThread = id;
						return Promise.resolve(id);
					});
			}
			else {
				Promise.resolve(id);
			}
		
	}

	function updateThreadStatus():Promise<Int> {
		return connection.sendCommand(WhereAllThreads)
			.then(function(message) {
				switch (message) {
					case ThreadsWhere(list):
						debuggerState.setThreadsStatus(list);

					default:
						'UNEXPECTED: $message';
				}
				return Promise.resolve(0);
			});
	}

	function onInfoMessage(message:Message) {
		trace('onInfoMessage: $message');
		switch (message) {
			case ThreadStopped(number, _):
				updateThreadStatus()
					.then(function(_) {
						sendThreadStatusEvent(number);
					});

			case ThreadStarted(number):
				debuggerState.setThreadRunning(number);
				sendThreadStatusEvent(number);

			case ThreadCreated(number):
				debuggerState.createThread(number);
				//sendThreadStatusEvent(number);
				
			default:
		}
		//sendEvent(new StoppedEvent("entry", num));
	}

	function sendThreadStatusEvent(number:Int) {
		var thread = debuggerState.threads[number];
		switch (thread.status) {
			case StoppedImmediate:
				trace('checkThreads StoppedImmediate');
				sendEvent(new StoppedEvent("entry", thread.id));

			case StoppedBreakpoint(number):
				sendEvent(new StoppedEvent("breakpoint", thread.id));
			
			case StoppedUncaughtException:
				sendEvent(new StoppedEvent("exception", thread.id));
				
			case StoppedCriticalError(description):
				sendEvent(new StoppedEvent("exception", thread.id));

			case Running:
				trace('CONTINUE: ${thread.id}');				
				//sendEvent(new ContinuedEvent(thread.id));
				trace("AFTER");
		}
	}

    static function main() {
        adapter.DebugSession.run(Main);
    }
}