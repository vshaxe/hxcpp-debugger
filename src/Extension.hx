import js.node.ChildProcess;
import vscode.*;
import Vscode.*;

class Extension {
	@:keep
	@:expose("activate")
	static function main(context:ExtensionContext) {
		commands.registerCommand("hxcpp-debugger.setup", function() {
			ChildProcess.spawn("haxelib", ["dev", "hxcpp-debug-server", context.asAbsolutePath("hxcpp-debug-server")], {});
		});
		commands.executeCommand("hxcpp-debugger.setup");
	}
}
