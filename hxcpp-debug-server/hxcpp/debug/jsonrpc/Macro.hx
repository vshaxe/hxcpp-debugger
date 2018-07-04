package hxcpp.debug.jsonrpc;

import haxe.macro.Context;

class Macro {
    macro public static function injectServer():Void {
        if (Context.defined("cpp")) {
            Context.getType("hxcpp.debug.jsonrpc.Server");
        }
    }

    macro public static function getDefinedValue(key:String, defaultV) {
        var val = Context.definedValue(key);
        return (val == null) ? macro ${defaultV} : macro $v{val};
    }
}
