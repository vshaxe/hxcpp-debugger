import js.Promise;
import protocol.debug.Types;
import js.node.Buffer;
import js.node.Net;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess.ChildProcessEvent;
import js.node.net.Socket;
import js.node.stream.Readable.ReadableEvent;
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
		//response.body.supportsConfigurationDoneRequest = true;
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
				}).then(function(_) {
					sendResponse(response);
					sendEvent(new adapter.DebugSession.InitializedEvent());
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

			var b:Breakpoint = {
				verified:true,
				source:args.source,
				line:bs.line,
				column:bs.column
			};
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

		sendResponse(response);
	}

	override function threadsRequest(response:ThreadsResponse):Void {
		trace('threadsRequest');
		connection.sendCommand(WhereAllThreads)
			.then(function(message) {
				switch (message) {
					case ThreadsWhere(list):
						debuggerState.setThreadsStatus(list);
					default:
						'UNEXPECTED: $message';
				}
				var threads = debuggerState.threads;
				response.body = {
					threads:[]
				};
				for (t in threads) {
					response.body.threads.push({
						id:t.id,
						name:t.name
					});
				}
				trace(haxe.Json.stringify(response.body.threads));
				sendResponse(response);
			});
	}

    static function main() {
        adapter.DebugSession.run(Main);
    }
}