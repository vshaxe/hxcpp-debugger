import debugger.IController;
import protocol.debug.Types;
import debugger.IController;
import adapter.Handles;
import DebuggerState;

typedef SubVar = {name:String, value:StructuredValue};

enum ReferenceVal {
    LocalsScope(frameId:Int, variables:Map<String, Variable>);
    StructuredVariable(reference:String, ?names:Array<SubVar>);
}

class StoppedFrame {

    public var id:Int;
    public var handles:Handles<ReferenceVal>;

    public function new(id:Int) {
        handles = new Handles<ReferenceVal>();
    }

    public function parseList(value:StructuredValue):Array<Variable> {
         var result = [];
         switch (value) {
            case List(type, list):
                while (true) {
                    switch (list) {
                        case Terminator:
                            break;
                        case Element(name, value, next):
                            result.push(getVariable(name, value));
                            list = next;
                    }
                }
            default:
                throw "unexpected";
         }
        return result;
    }

    public function getVariable(name:String, value:StructuredValue):Variable {
        return switch (value) {
            case List(type, list):
                createStructured(name, type, list);

            case Single(type, value):
                createVariable(name, value);
                
            case Elided(type, getExpression):
                var ref = handles.create(StructuredVariable(getExpression));
                createVariable(name, parseType(type), ref, parseType(type));
        }
    }

    function createStructured(name:String, type:StructuredValueListType, list:StructuredValueList):Variable {
        var inner = [];
        var ref = handles.create(StructuredVariable(name, inner));
        var count = 0;
        var typeString:String = parseListType(type);
        //var result = new Variable(name,)
        while (true) {
            switch (list) {
                case Terminator:
                    break;
                case Element(name, value, next):
                    inner.push({name:name, value:value});
                    count++;
                    list = next;
            }
        }

        return switch (type) {
            case _Array: 
                createVariable(name, "", ref, typeString, count, null);

            default:  
                createVariable(name, "", ref, typeString, null, count);
        }
    }

    function parseListType(type:StructuredValueListType):String {
        return 
            switch (type) {
                case Anonymous: 'Anonymous';
                case _Array: 'Array';
                case Instance(className): 'Instance<$className>';
                case Class : 'Class';
            };
    }

    function parseType(type:StructuredValueType):String {
        return 
            switch (type) {
                case TypeInstance(className): 'Instance<$className>';            
                case TypeBool: "Bool";
                case TypeInt: "Int";
                case TypeFloat: "Float";
                case TypeString: "String";
                case TypeEnum(enumValue): 'Enum<$enumValue>';
                case TypeAnonymous(elements): 'Anonymous';
                case TypeClass(className): 'Class<$className>';
                case TypeFunction: 'Function';
                case TypeArray: 'Array';

                default:
                    "Any";
            };
    }

    function createVariable(name:String, value:String, refId:Int=0, ?type:String, ?indexedCount:Int, ?namedCount:Int):protocol.debug.Variable {
        var result:protocol.debug.Variable = {
            name:name,
            value:value,
            //kind:type,
            variablesReference:refId,
            type:type
        };
        if (indexedCount != null) result.indexedVariables = indexedCount;
        if (namedCount != null) result.namedVariables = namedCount;

        return result;
    }
}