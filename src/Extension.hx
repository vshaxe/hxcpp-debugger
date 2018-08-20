import vscode.*;
import Vscode.*;

class Extension {
	@:keep
	@:expose("activate")
	static function main(context:ExtensionContext) {
		commands.registerCommand("hxcpp-debugger.setup", function() {
			var terminal = window.createTerminal();
			terminal.sendText("haxelib dev hxcpp-debug-server " + context.asAbsolutePath("hxcpp-debug-server"));
			terminal.show();
		});
	}
}
