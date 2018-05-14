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
}

enum ReferenceVal {
    LocalsScope(frameId:Int)
    MembersScope(frameId:Int)
}

class DebuggerState {

    public var workspaceToAbsPath:Map<String, String>;
    public var absToWorkspace:Map<String, String>;
    public var threads:Map<Int, ThreadState>;
    public var initializing:Bool;
    public var handles:Handles<ReferenceVal>;
    
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
        handles = new Handles<ReferenceVal>();
    }

    public function getBreakpointsByPath(path:String, pathIsAbsolute:Bool = true):Array<Breakpoint> {
        return breakpoints.exists(path) ? breakpoints[path] : [];
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
                    threads[number] = {
                        id:number,
                        name:'Thread$number',
                        status:status,
                        where:parseFrameList(frameList)
                    };
                    list = next;

                case Terminator:
                    break;
            }
        }
    }

    public function updateThreadStatus(id:Int, message:Message) {
        
    }

    public function calcPathDictionaries() {
        for (i in 0...workspaceFiles.length) {
            workspaceToAbsPath[workspaceFiles[i]] = absFiles[i];
            absToWorkspace[absFiles[i]] = workspaceFiles[i];
        }
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