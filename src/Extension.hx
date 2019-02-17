import vscode.*;
import Vscode.*;

class Extension {
	@:keep
	@:expose("activate")
	static function main(context:ExtensionContext) {
		commands.registerCommand("hxcpp-debugger.setup", function() {
			var terminal = window.createTerminal();
			terminal.sendText("haxelib dev hxcpp-debug-server \"" + context.asAbsolutePath("hxcpp-debug-server") + "\"");
			terminal.show();
			context.globalState.update("previousExtensionPath", context.extensionPath);
		});

		if (isExtensionPathChanged(context)) {
			commands.executeCommand("hxcpp-debugger.setup");
		}
	}

	static function isExtensionPathChanged(context:ExtensionContext):Bool {
		var previousPath = context.globalState.get("previousExtensionPath");
		return (context.extensionPath != previousPath);
	}
}
