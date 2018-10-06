package hxcpp.debug.jsonrpc;

import hscript.Parser;
import hscript.Interp;

private enum Value {
	Single(val:Dynamic);
	IntIndexed(val:Dynamic, length:Int, fieldAccess:Dynamic->Int->Dynamic);
	StringIndexed(val:Dynamic, printedValue:String, names:Array<String>, fieldsAsString:Bool, fieldAccess:Dynamic->String->Dynamic);
	NameValueList(names:Array<String>, values:Array<Dynamic>);
}

class Eval {
	public static function evaluate(expression:String, threadId:Int, frameId:Int):String {
		var result = "not available";
		var stackVariables = cpp.vm.Debugger.getStackVariables(threadId, frameId, false);
		try {
			var parser = new hscript.Parser();
			var ast = parser.parseString(expression);
			var interp = new hscript.Interp();
			for (vname in stackVariables) {
				trace(vname);
				var v = cpp.vm.Debugger.getStackVariableValue(threadId, frameId, vname, false);
				interp.variables.set(vname, v);
				if (vname == "this") {
					var members = Reflect.fields(v);
					for (m in members) {
						interp.variables.set(m, Reflect.getProperty(v, m));
					}
				}
			}
			interp.variables.set('Reflect', Reflect);
			var v = interp.execute(ast);
			if (v != null) {
				result = v.toString();
			}
		} catch (e:Dynamic) {}

		return result;
	}
}
