import debugger.IController;
import js.Promise;
import protocol.debug.Types;
import adapter.DebugSession;

typedef ThreadState = {
    var id:Int;
    var name:String;
    var status:ThreadStatus;
    var where:Array<StackFrame>;
}

class DebuggerState {

    public var workspaceToAbsPath:Map<String, String>;
    public var absToWorkspace:Map<String, String>;
    public var threads:Map<Int, ThreadState>;

    var breakpoints:Map<String, Array<Breakpoint>>;
    var workspaceFiles:Array<String>;
    var absFiles:Array<String>;

    public function new() {
        breakpoints = new Map<String, Array<Breakpoint>>();
        workspaceToAbsPath = new Map<String, String>();
        absToWorkspace = new Map<String, String>();
        workspaceFiles = [];
        absFiles = [];
    }

    public function getBreakpointsByPath(path:String, pathIsAbsolute:Bool=true) {
        return breakpoints.exists(path) ? breakpoints[path] : [];
    }

    public function setWorkspaceFiles(files:Array<String>) {
        workspaceFiles = files;
    }

    public function setAbsFiles(files:Array<String>) {
        absFiles = files;
    }

    public function setThreadsStatus(list:ThreadWhereList) {
        threads = new Map<Int, ThreadState>();
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

    public function calcPathDictionaries() {
        for (i in 0...workspaceFiles.length) {
            workspaceToAbsPath[workspaceFiles[i]] = absFiles[i];
            absToWorkspace[absFiles[i]] = workspaceFiles[i];
        }
    }

    function parseFrameList(frameList:FrameList) {
        var result = [];
        while (true) {
            switch (frameList) {
                case Frame(isCurrent, num, className, functionName, file, line, next):
                    result.push(cast new StackFrame(num, '$className.$functionName', new Source(className, file), line));
                    frameList = next;

                case Terminator:
                   break;
            }
        }

        return result;
    }
}