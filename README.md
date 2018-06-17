# Howto use
after install `hxcpp-debug-jsonrpc` library is available. And can be using with your project.

for eg:
build.hxml:
```
-lib hxcpp-debug-jsonrpc
```

openfl project.xml:
```
<haxelib name="hxcpp-debug-jsonrpc" if="debug" />
```

Main.hx
```
#if debug
new hxcpp.debug.jsonrpc.Server('127.0.0.1', 6972);
#end
```

# Installing from source
Navigate to the extensions folder (C:\Users\<username>\.vscode\extensions on Windows, ~/.vscode/extensions otherwise)

Clone this repo: git clone https://github.com/vshaxe/vscode_hxcpp_debugger

Change current directory to the cloned one: cd vscode_hxcpp_debugger.

Install dependencies:

npm install
haxelib install hxnodejs
haxelib git vscode-debugadapter https://github.com/vshaxe/vscode-debugadapter-extern
Do haxe build.hxml
