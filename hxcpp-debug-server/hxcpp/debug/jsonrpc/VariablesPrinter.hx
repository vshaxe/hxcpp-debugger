package hxcpp.debug.jsonrpc;

enum VarType {
	TypeNull;
	TypeInt;
	TypeFloat;
	TypeBool;
	TypeClass(name:String);
	TypeAnonymous(fieldsCount:Int);
	TypeFunction;
	TypeEnum(name:String);
}

enum Value {
	Single(val:Dynamic);
	IntIndexed(val:Dynamic, length:Int, fieldAccess:Dynamic->Int->Dynamic);
	StringIndexed(val:Dynamic, printedValue:String, names:Array<String>, fieldsAsString:Bool, fieldAccess:Dynamic->String->Dynamic);
	NameValueList(names:Array<String>, values:Array<Dynamic>);
}

typedef Variable = {
	var name:String;
	var type:String;
	var value:Value;
}

class VariablesPrinter {
	public static function getInnerVariables(value:Value, start:Int = 0, count:Int = -1):Array<Variable> {
		var result = [];
		switch (value) {
			case NameValueList(names, values):
				if (count < 0)
					count = names.length - start;
				for (i in start...start + count) {
					var name = names[i];
					var value = values[i];
					if (value == null)
						continue;
					result.push({
						name: name,
						value: resolveValue(value),
						type: getType(value)
					});
				}

			case StringIndexed(val, _, names, fieldsAsString, fieldAccess):
				if (count < 0)
					count = names.length;
				var filteredNames = names.slice(start, start + count);
				for (n in filteredNames) {
					var value = fieldAccess(val, n);
					result.push({
						name: if (fieldsAsString) '"$n"' else n,
						value: resolveValue(value),
						type: getType(value)
					});
				}

			case IntIndexed(val, length, fieldAccess):
				if (count < 0)
					count = length;
				for (i in start...start + count) {
					var value = fieldAccess(val, i);
					result.push({
						name: '$i',
						value: resolveValue(value),
						type: getType(value)
					});
				}

			case Single(_):
				throw "not structured";
		}
		return result;
	}

	public static function resolveValue(value:Dynamic):Value {
		return switch (Type.typeof(value)) {
			case TNull, TUnknown, TInt, TFloat, TBool, TFunction:
				Single(value);

			case TClass(String):
				Single('"$value"');

			case TEnum(e):
				Single(Std.string(value));

			case TObject:
				StringIndexed(value, Std.string(value), Reflect.fields(value), false, propGet);

			case TClass(Array):
				var arr:Array<Dynamic> = cast value;
				IntIndexed(value, arr.length, arrayGet);

			case TClass(haxe.ds.StringMap):
				var map:haxe.ds.StringMap<Dynamic> = cast value;
				var keys = [for (k in map.keys()) '$k'];
				StringIndexed(value, Std.string(value), keys, true, stringMapGet);

			case TClass(haxe.ds.IntMap):
				var map:haxe.ds.IntMap<Dynamic> = cast value;
				var keys = [for (k in map.keys()) '$k'];
				StringIndexed(value, Std.string(value), keys, false, intMapGet);

			case TClass(c):
				var all = getClassProps(c);
				var className = Type.getClassName(Type.getClass(value));
				var dotIndex = className.lastIndexOf(".");
				if (dotIndex != -1) {
					className = className.substr(dotIndex + 1);
				}
				var printedValue = className + ", " + Std.string(value);
				StringIndexed(value, printedValue, [
					for (f in all)
						if (!Reflect.isFunction(propGet(value, f)))
							f], false, propGet);
		}
	}

	public static function evaluate(expression:String, threadId:Int, frameId:Int):Null<Variable> {
		var result = null;
		var fields = expression.split(".");
		var stackVariables = cpp.vm.Debugger.getStackVariables(threadId, frameId, false);
		if (stackVariables.indexOf(fields[0]) == -1) {
			// try with `this.`
			fields.unshift("this");
		}
		var root:Dynamic = null;
		var current = null;
		for (f in fields) {
			if (f.indexOf("[") >= 0) {
				break; // TODO
			} else {
				if (root == null) {
					root = cpp.vm.Debugger.getStackVariableValue(threadId, frameId, f, false);
					current = root;
				} else {
					current = propGet(current, f);
				}
				if (current == null) {
					result = null;
					break; // can't evaluate
				}

				result = {
					name: expression,
					value: VariablesPrinter.resolveValue(current),
					type: VariablesPrinter.getType(current)
				}
			}
		}
		return result;
	}

	static function getClassProps(c:Class<Dynamic>) {
		var fields = [];
		try {
			var flds = Type.getInstanceFields(c);
			for (f in flds) {
				fields.push(f);
			}
		} catch (e:Dynamic) {
			trace('error:$e');
		}
		// TODO: statics
		return fields;
	}

	public static function getType(value:Dynamic):String {
		switch (Type.typeof(value)) {
			case TNull, TUnknown:
				return "Unknown";

			case TInt:
				return "Int";

			case TFloat:
				return "Float";

			case TBool:
				return "Bool";

			case TObject:
				if (Std.is(value, Class)) {
					return getClassName(cast value);
				}
				return "Anonymous";

			case TFunction:
				return "Function";

			case TEnum(e):
				return Type.getEnumName(e);

			case TClass(String):
				return "String";

			case TClass(Array):
				return "Array";

			case TClass(c):
				return getClassName(c);
		}
		return null;
	}

	static function getClassName(klass:Class<Dynamic>):String {
		var className:String = "<unknown class name>";
		if (null != klass) {
			var klassName:String = Type.getClassName(klass);
			if (null != klassName && 0 != klassName.length) {
				className = klassName;
			}
		}
		return className;
	}

	public static function toString(varType:VarType):String {
		return "";
	}

	public static function arrayGet(value:Dynamic, index:Int):Dynamic {
		var arr:Array<Dynamic> = cast value;
		return arr[index];
	}

	public static function propGet(value:Dynamic, key:String):Dynamic {
		var propVal = null;
		try {
			propVal = Reflect.getProperty(value, key);
			if (propVal == null)
				propVal = Reflect.field(value, key);
		} catch (e:Dynamic) {
			trace(e);
		}
		return propVal;
	}

	public static function stringMapGet(value:Dynamic, key:String):Dynamic {
		var map:Map<String, Dynamic> = cast value;
		return map.get(key);
	}

	public static function intMapGet(value:Dynamic, key:String):Dynamic {
		var map:Map<Int, Dynamic> = cast value;
		return map.get(Std.parseInt(key));
	}
}
