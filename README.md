# Howto use
after install you need to include `hxcpp-debug-server` library into your project:

* build.hxml
```
-lib hxcpp-debug-server
```

* openfl project.xml:
```
<haxelib name="hxcpp-debug-server" if="debug" />
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
