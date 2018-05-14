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
			//targetProcess.stdout.on(ReadableEvent.Data, onStdout);
			//targetProcess.stderr.on(ReadableEvent.Data, onStderr);
			targetProcess.on(ChildProcessEvent.Exit, onExit);
		});
	}

	override function configurationDoneRequest(response:ConfigurationDoneResponse, args:ConfigurationDoneArguments):Void {
		trace("configurationDoneRequest");
		sendResponse(response);
		connection.sendCommand(SetCurrentThread(0))
			.then(function(message) {
				return connection.sendCommand(Continue(1));
			})
			.then(function(message:Message) {
				trace('continue result: $message');
			});
	}

	override function continueRequest(response:ContinueResponse, args:ContinueArguments):Void {
		connection.sendCommand(SetCurrentThread(args.threadId))
			.then(function(message) {
				return connection.sendCommand(Continue(1));
			})
			.then(function(message:Message) {
				switch (message) {
					case OK:
						sendResponse(response);

					case ErrorBadCount(count):
						
					default:
						trace('UNEXPECTED MESSAGE: $message');
				}
			});
	}

	override function setBreakPointsRequest(response:SetBreakpointsResponse, args:SetBreakpointsArguments):Void {
		trace('args1: ${haxe.Json.stringify(args)}');

		var breakpoints = debuggerState.getBreakpointsByPath(args.source.path);
		var alreadySet = [for (b in breakpoints) b.line => b];
		var newBreakpoints = [];
		response.body = {
			breakpoints:newBreakpoints
		};

		for (bs in args.breakpoints) {
			if (alreadySet.exists(bs.line))
				continue;

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

		last.then(function(_) {
			trace(haxe.Json.stringify(response));
			sendResponse(response);
		});
	}

	override function scopesRequest(response:ScopesResponse, args:ScopesArguments):Void {
		trace('scopes');
		trace('args1: ${haxe.Json.stringify(args)}');

		var scopes:Array<Scope> = [
            new ScopeImpl("Locals", debuggerState.handles.create(LocalsScope(args.frameId)), false),
            new ScopeImpl("Members", debuggerState.handles.create(MembersScope(args.frameId)), false)
		];

        response.body = {
            scopes: cast scopes
        };
		
		sendResponse(response);
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
				sendResponse(response);
			});
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
				updateThreadStatus()
					.then(function(_) {
						sendThreadStatusEvent(number);
					});
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
				sendEvent(new ContinuedEvent(thread.id));
		}
	}

    static function main() {
        adapter.DebugSession.run(Main);
    }
}