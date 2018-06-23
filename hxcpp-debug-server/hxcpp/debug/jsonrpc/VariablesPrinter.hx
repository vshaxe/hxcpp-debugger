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
    IntIndexed(val:Dynamic, length:Int);
    StringIndexed(val:Dynamic, names:Array<String>);
    NameValueList(names:Array<String>, values:Array<Dynamic>);
}

typedef Variable = {
    var name:String;
    var type:String;
    var value:Value;
}

class VariablesPrinter {

    public static function getInnerVariables(value:Value, start:Int=0, count:Int=-1):Array<Variable> {
        var result = [];
        switch (value) {
            case NameValueList(names, values):
                if (count < 0) count = names.length - start;
                for (i in start...start + count) {
                    var name = names[i];
                    var value = values[i];
                    if (value == null) continue;
                    result.push({
                        name:name,
                        value:resolveValue(value),
                        type:getType(value)
                    });
                }

            case StringIndexed(val, names):
                if (count < 0) count = names.length;
                var filteredNames = names.slice(start, start + count);
                for (n in filteredNames) {
                    var value = Reflect.getProperty(val, n);
                    if (value == null) value = Reflect.field(val, n);
                    result.push({
                        name:n,
                        value:resolveValue(value),
                        type: getType(value)
                    });
                }
            
            case IntIndexed(val, length) if (getType(val) == "Array"):
                if (count < 0) count = length;
                trace('start: $start, count:$count, end: ${start + count}');
                for (i in start...start + count) {
                    var value = val[i];
                    result.push({
                        name:'$i',
                        value:resolveValue(value),
                        type: getType(value)
                    });
                }
                trace(result);

             case IntIndexed(val, length):
                if (count < 0) count = length;
                trace('start: $start, count:$count, end: ${start + count}');
                for (i in start...start + count) {
                    var value = val.get(i);
                    if (value == null) continue;
                    result.push({
                        name:'$i',
                        value:resolveValue(value),
                        type: getType(value)
                    });
                }
                trace(result);

            case Single(_):
                throw "not structured";
        }
        return result;
    }

    public static function resolveValue(value:Dynamic):Value {
        return switch (Type.typeof(value)) {
            case TNull, TUnknown, TInt, TFloat, TBool, TFunction, TClass(String):
                Single(value);

            case TEnum(e):
                //TODO
                Single(value);

            case TObject:
                StringIndexed(value, Reflect.fields(value));

            case TClass(Array):
                var arr:Array<Dynamic> = cast value;
                IntIndexed(value, arr.length);

            case TClass(haxe.ds.IntMap):
                var map:haxe.ds.IntMap<Dynamic> = cast value;
                var keys = [for (k in map.keys()) '$k'];
                IntIndexed(value, keys.length);

            case TClass(c):
                var all = getClassProps(c);
                
                StringIndexed(value, [for (f in all) 
                    if (!Reflect.isFunction(Reflect.getProperty(value, f))) 
                        f]);
        }
    }

     public static function evaluate(expression:String, threadId:Int, frameId:Int):Null<Variable> {
        var result = null;
        var fields = expression.split(".");
        var root:Dynamic = null;
        var current = null;
        for (f in fields) {
            if (f.indexOf("[") >= 0) {
                break; //TODO
            }
            else {
                if (root == null) {
                    root = cpp.vm.Debugger.getStackVariableValue(threadId, frameId, f, false);
                    current = root;
                }
                else {
                    current = Reflect.getProperty(current, f);
                }
                if (current == null) {
                    result = null;
                    break; //can't evaluate
                }

                result = {
                    name:expression,
                    value:VariablesPrinter.resolveValue(current),
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
        }
        catch(e:Dynamic) {
            trace('error:$e');
        }
        //TODO: statics
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

    static function getClassName(klass:Class<Dynamic>) : String {
        var className : String = "<unknown class name>";
        if (null != klass) {
           var klassName : String = Type.getClassName(klass);
            if (null != klassName && 0 != klassName.length) {
                className = klassName;
            }
        }
        return className;
    }

    public static function toString(varType:VarType):String {
        return "";
    }
}