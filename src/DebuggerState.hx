import debugger.IController;
import js.Promise;
import protocol.debug.Types;
import adapter.DebugSession;
import adapter.Handles;

typedef ThreadState = {
    var id:Int;
    var name:String;
    var status:ThreadStatus;
    var where:Array<StackFrame>;
    var handles:Handles<ReferenceVal>;
    var currentFrame:Int;
}

enum ReferenceVal {
    LocalsScope(frameId:Int, variables:Map<String, Variable>);
    //MembersScope(frameId:Int, variables:Map<String, Variable>);
}

class DebuggerState {

    public var workspaceToAbsPath:Map<String, String>;
    public var absToWorkspace:Map<String, String>;
    public var threads:Map<Int, ThreadState>;
    public var initializing:Bool;
    public var currentThread:Int = 0;
    
    var breakpoints:Map<String, Array<Breakpoint>>;
    var workspaceFiles:Array<String>;
    var absFiles:Array<String>;

    public function new() {
        breakpoints = new Map<String, Array<Breakpoint>>();
        workspaceToAbsPath = new Map<String, String>();
        absToWorkspace = new Map<String, String>();
        threads = new Map<Int, ThreadState>();
        workspaceFiles = [];
        absFiles = [];
    }

    public function getBreakpointsByPath(path:String, pathIsAbsolute:Bool = true):Array<Breakpoint> {
        return breakpoints.exists(path) ? breakpoints[path] : [];
    }

    public function setBreakpointsByPath(path:String, v:Array<Breakpoint>) {
        breakpoints[path] = v;
    }

    public function setWorkspaceFiles(files:Array<String>) {
        workspaceFiles = files;
    }

    public function setAbsFiles(files:Array<String>) {
        absFiles = files;
    }

    public function setThreadsStatus(list:ThreadWhereList) {
        while (true) {
            switch (list) {
                case Where(number, status, frameList, next):
                    var thread = getOrCreateThread(number);
                    thread.status = status;
                    thread.where = parseFrameList(frameList);
                    list = next;
                

                case Terminator:
                    break;
            }
        }
    }

    public function createThread(id:Int) {
        var status = ThreadStatus.Running;
        
        threads[id] = {
            id:id,
            name:'Thread$id',
            status:status,
            where:[],
            handles:new Handles<ReferenceVal>(),
            currentFrame:-1
        };
        trace(threads[id]);

        return threads[id];
    }

    public function getOrCreateThread(id:Int) {
        return (threads.exists(id)) ? threads[id] : createThread(id);
    }

    public function setThreadRunning(id:Int) {
        var thread = getOrCreateThread(id);
        thread.status = Running;
        thread.handles.reset();
    }

    public function calcPathDictionaries() {
        for (i in 0...workspaceFiles.length) {
            workspaceToAbsPath[workspaceFiles[i]] = absFiles[i];
            absToWorkspace[absFiles[i]] = workspaceFiles[i];
        }
    }

    public function getCurrentThread():ThreadState {
        return threads[currentThread];
    }

    public function getHandles():Handles<ReferenceVal> {
        return getCurrentThread().handles;
    }

    function parseFrameList(frameList:FrameList):Array<StackFrame> {
        var result = [];
        while (true) {
            switch (frameList) {
                case Frame(isCurrent, num, className, functionName, file, line, next):
                    var fullPath = workspaceToAbsPath.exists(file) ? workspaceToAbsPath[file] : file;
                    trace(fullPath);
                    result.push(cast new StackFrame(num, '$className.$functionName', new Source(className, fullPath), line));
                    frameList = next;

                case Terminator:
                   break;
            }
        }

        return result;
    }
}