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
}

typedef Variable = {
    var name:String;
    var type:String;
    var value:Value;
}

class VariablesPrinter {

    public static function printVariables(nameVal:Map<String, Dynamic>):Array<Variable> {
        var result = [];
        for (name in nameVal.keys()) {
            var value = nameVal[name];
            if(value == null) continue;

            var type:String = getType(value);
            result.push({
                name:name,
                value:resolveValue(value),
                type:type
            });
        }
        return result;
    }

    public static function getInnerVariables(value:Value, start:Int=0, count:Int=-1):Array<Variable> {
        var result = [];
        switch (value) {
            case StringIndexed(val, names):
                if (count < 0) count = names.length;
                var filteredNames = names.slice(start, start + count);
                for (n in filteredNames) {
                    var value = Reflect.getProperty(val, n);
                    result.push({
                        name:n,
                        value:resolveValue(value),
                        type: getType(value)
                    });
                }
            
            case IntIndexed(val, length):
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

            case Single(_):
                throw "not structured";
        }
        return result;
    }

    static function resolveValue(value:Dynamic):Value {
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

            case TClass(c):
                StringIndexed(value, getClassProps(c));
        }
    }

    static function getClassProps(c:Class<Dynamic>) {
        //TODO: statics
        return Type.getInstanceFields(c);
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