package hxcpp.debug.jsonrpc;

#if cpp
import cpp.vm.Thread;
import cpp.vm.Mutex;
import cpp.vm.Debugger;
import cpp.vm.Deque;
#else
typedef Mutex = Dynamic;
#end
import hxcpp.debug.jsonrpc.VariablesPrinter;
import hxcpp.debug.jsonrpc.Protocol;

@:enum abstract ScopeId(String) to String {
    var members = "Members";
    var locals = "Locals";
}

enum Reference {
    Scope(scopeId:ScopeId, vars:Map<String, Dynamic>);
    Var(value:Value);
}

private class References {
    var lastId:Int;
    var references:Map<Int, Reference>;

    public function new() { 
        lastId = 1000;
        references = new Map<Int, Reference>();
    }

    public function create(ref:Reference):Int {
        var id = lastId;
        references[lastId] = ref;
        lastId++;
        return id;
    }

    public function get(id:Int):Reference {
        return references[id];
    }
}

class Server {

    var host:String;
    var port:Int;
    var socket:sys.net.Socket;
    var stateMutex:Mutex;
    var currentThreadInfo:cpp.vm.ThreadInfo;
    var scopes:Map<ScopeId, Array<String>>;
    var references:References;
    var started:Bool;

    static var startQueue:Deque<Bool> = new Deque<Bool>();

    public function new(host:String, port:Int=6972) {
        this.host = host;
        this.port = port;
        stateMutex = new Mutex();
        scopes = new Map<ScopeId, Array<String>>();
        references = new References();
        
        connect();

        Debugger.enableCurrentThreadDebugging(false);
        Thread.create(debuggerThreadMain);
        startQueue.pop(true);
        Debugger.enableCurrentThreadDebugging(true);
    }

    private function connect() {
        var socket : sys.net.Socket = new sys.net.Socket();

        while (true) {
            try {
                var host = new sys.net.Host(host);
                if (host.ip == 0) {
                    throw "Name lookup error.";
                }
                socket.connect(host, port);
                log('Connected to vsc debugger server at $host:$port');

                this.socket = socket;
                return;
            }
            catch (e : Dynamic) {
                log('Failed to connect to vsc debugger server at $host:$port');
            }
            closeSocket();
            log("Trying again in 3 seconds.");
            Sys.sleep(3);
        }
    }

    private function debuggerThreadMain() {
       // Debugger.setEventNotificationHandler();
       Debugger.setEventNotificationHandler(handleThreadEvent);
       Debugger.enableCurrentThreadDebugging(false);
       Debugger.breakNow(true);
       var fullPathes = Debugger.getFilesFullPath();
       var files = Debugger.getFiles();
       var path2file = new Map<String, String>();
       var file2path = new Map<String, String>();
       for (i in 0...files.length) {
           var file = files[i];
           var path = fullPathes[i];
           path2file[path] = file;
           file2path[file] = path;
       }
       startQueue.push(true);

        try {
            while (true) {
                var m = readMessage();
                switch (m.method) {
                    case Protocol.SetBreakpoints:
                        var params:SetBreakpointsParams = m.params;
                        var result = [];
                        trace('Protocol.SetBreakpoints: $params');
                        for (b in params.breakpoints) {
                            var id = Debugger.addFileLineBreakpoint(path2file[params.file], b.line);
                            result.push(id);
                        }
                        m.result = result;
                        sendResponse(m);

                    case Protocol.Continue:
                        Debugger.continueThreads(m.params.threadId, 1);
                        sendResponse(m);

                    case Protocol.Threads:
                        var threadInfo:Array<cpp.vm.ThreadInfo> = Debugger.getThreadInfos();
                        m.result = [for (ti in threadInfo) {id:ti.number, name:'Thread${ti.number}'}];
                        sendResponse(m);

                    case Protocol.GetScopes:
                        references = new References();
                        function getProp(value:Dynamic, propName:String) {
                            return Reflect.getProperty(value, propName);
                        }

                        var threadId = 0; //TODO: map it to frameId?
                        var frameId = m.params.frameId;
                        m.result = [];
                        var stackVariables:Array<String> = Debugger.getStackVariables(threadId, frameId, false);
                        var localsInner = null;
                        for (varName in stackVariables) {
                            if (varName == "this") {
                                var inner = new Map<String, Dynamic>();
                                var id = references.create(Scope(ScopeId.members, inner));
                                m.result.push({id:id, name:ScopeId.members});

                                var value:Dynamic = Debugger.getStackVariableValue(threadId, frameId, "this", false);
                                var valueType = Type.getClass(value);
                                for (m in Type.getInstanceFields(valueType)) {
                                    inner[m] = getProp(value, m);
                                } 
                                for (s in Type.getClassFields(valueType)) {
                                    inner[s] = getProp(value, s);
                                }
                            } else {
                                if (localsInner == null) {
                                    localsInner = new Map<String, Dynamic>();
                                    var id = references.create(Scope(ScopeId.locals, localsInner));
                                    m.result.push({id:id, name:ScopeId.locals});
                                }
                                var value:Dynamic = Debugger.getStackVariableValue(threadId, frameId, varName, false);
                                localsInner[varName] = value;
                            }
                        }
                        sendResponse(m);

                    case Protocol.GetVariables:
                        m.result = [];
                        var refId = m.params.variablesReference;
                        var ref:Reference = references.get(refId);
                        switch (ref) {
                            case Scope(scopeId, inner):
                                var vars = VariablesPrinter.printVariables(inner);
                                trace(vars);
                                for (v in vars) {
                                    var varInfo:VarInfo = {
                                        name:v.name,
                                        type:v.type,
                                        value:"",
                                        variablesReference:0,
                                    }
                                    switch (v.value) {
                                        case IntIndexed(value, length):
                                            var refId = references.create(Var(v.value));
                                            varInfo.variablesReference = refId;
                                            varInfo.indexedVariables = length;

                                        case StringIndexed(value, names):
                                            var refId = references.create(Var(v.value));
                                            varInfo.variablesReference = refId;
                                            varInfo.namedVariables = names.length;

                                        case Single(value):
                                            varInfo.value = value;
                                    }
                                    m.result.push(varInfo);
                                }

                            case Var(value):
                                var vars = VariablesPrinter.getInnerVariables(value, m.params.start, m.params.count);
                                //trace(vars);
                                for (v in vars) {
                                    var varInfo:VarInfo = {
                                        name:v.name,
                                        type:v.type,
                                        value:"",
                                        variablesReference:0,
                                    }
                                    switch (v.value) {
                                        case IntIndexed(value, length):
                                            var refId = references.create(Var(v.value));
                                            varInfo.variablesReference = refId;
                                            varInfo.indexedVariables = length;

                                        case StringIndexed(value, names):
                                            var refId = references.create(Var(v.value));
                                            varInfo.variablesReference = refId;
                                            varInfo.namedVariables = names.length;

                                        case Single(value):
                                            varInfo.value = value;
                                    }
                                    m.result.push(varInfo);
                                }
                               
                        }
                        sendResponse(m);


                    case Protocol.StackTrace:
                        var threadInfo = Debugger.getThreadInfo(m.params.threadId, false);
                        m.result = [];
                        for (s in threadInfo.stack) {
                            if (s.className == "debugger.VSCodeRemote") break;
                            var frameNumber = threadInfo.stack.length - 1;
                            m.result.unshift({
                                id:frameNumber,
                                name:'${s.className}.${s.functionName}',
                                source:file2path[s.fileName],
                                line:s.lineNumber,
                                column:0,
                                artificial:false
                            });
                        }
	                    sendResponse(m);

                    case Protocol.Next:
                        Debugger.stepThread(0, Debugger.STEP_OVER, 1);
                        sendResponse(m);

                }
                trace('Message: $m');
            }
        }
    }

    private function readMessage():Message {
        var length:Int = socket.input.readInt16();
        trace('Message Length: $length');
        var rawString = socket.input.readString(length);
        return haxe.Json.parse(rawString);
    }

    private function sendResponse(m:Message) {
        var serialized:String = haxe.Json.stringify(m);
        socket.output.writeInt16(serialized.length);
        socket.output.writeString(serialized);
    }

    private function sendEvent<T>(event:NotificationMethod<T>, ?params:T) {
        var m = {
            method:event,
            params:params
        };
        sendResponse(m);
    }

    function handleThreadEvent(threadNumber : Int, event : Int,
                                       stackFrame : Int,
                                       className : String,
                                       functionName : String,
                                       fileName : String, lineNumber : Int)
    {
        trace(event);
        //if (!started) return;

        switch (event) {
            case Debugger.THREAD_CREATED:
                //emit(ThreadCreated(threadNumber));
            case Debugger.THREAD_TERMINATED:
            /*
                mStateMutex.acquire();
                if (threadNumber == mCurrentThreadNumber) {
                    mCurrentThreadInfo = null;
                }
                mStateMutex.release();
                emit(ThreadTerminated(threadNumber));
            */    
            case Debugger.THREAD_STARTED:
            /*
                mStateMutex.acquire();
                if (threadNumber == mCurrentThreadNumber) {
                    mCurrentThreadInfo = null;
                }
                mStateMutex.release();
                emit(ThreadStarted(threadNumber));
            */   
            case Debugger.THREAD_STOPPED:
                
                stateMutex.acquire();
                currentThreadInfo = Debugger.getThreadInfo(threadNumber, false);
                stateMutex.release();

                if (currentThreadInfo.status == cpp.vm.ThreadInfo.STATUS_STOPPED_BREAK_IMMEDIATE) {

                }
                else if (currentThreadInfo.status == cpp.vm.ThreadInfo.STATUS_STOPPED_BREAKPOINT) {
                    sendEvent(Protocol.BreakpointStop, {threadId:threadNumber});
                }
                else {
                    sendEvent(Protocol.ExceptionStop);
                }
                //ThreadStopped(threadNumber, stackFrame, className,
                //                functionName, fileName, lineNumber));
         
        }
    }

    function printVariables(names:String) {

    }

    private function closeSocket() {
        if (socket != null) {
            socket.close();
            socket = null;
        }
    }

    public static function log(message:String) {
        trace(message);
    }
}