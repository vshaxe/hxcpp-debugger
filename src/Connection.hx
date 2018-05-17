import debugger.IController.Command;
import debugger.IController.Message;
import js.node.stream.Readable.ReadableEvent;
import js.node.events.EventEmitter;
import js.node.net.Socket;
import js.node.Buffer;
import js.Promise;
import debugger.HaxeProtocol;

private class SocketOutStream extends haxe.io.Output {
    var socket:Socket;
    var buffer:js.node.Buffer;
    var offset:Int;

    public function new(socket:Socket) {
        this.socket = socket;
        buffer = new Buffer(1);
        offset = 0;
    }

    override public function writeByte(c:Int):Void {
        buffer.writeInt8(c, 0);
		socket.write(buffer);
	}
}

private class SocketInStream extends haxe.io.Input {
    static inline var BUFFER_SIZE = 4096;

    var socket:Socket;
    var buffer:Buffer;
    var index:Int;
    var readIndex:Int;
    var resolveOnEnoughData:Int -> Void;
    var waitBytesCount:Int;

    public function new(socket:Socket) {
        this.socket = socket;
        buffer = new Buffer(BUFFER_SIZE);
        index = 0;
        readIndex = 0;
        socket.on(ReadableEvent.Data, onData);
    }

    override public function readByte():Int {
        var byte = buffer.readInt8(readIndex);
        readIndex++;

        //compress every 64 byte read
        if (readIndex == 64) {
           buffer.copy(buffer, 0, readIndex, index);
           index -= readIndex;
           readIndex = 0;
        }
        return byte;
	}

    public function waitForData(numBytes:Int):Promise<Int> {
        trace('waitForData: $numBytes, $readIndex:$index');
        if (resolveOnEnoughData != null) {
            throw "only one waiter at a time is possible";
        }
        
        return if (dataLength() >= numBytes) {
            Promise.resolve(dataLength());
        }
        else {
            new Promise<Int>(function(resolve, reject) {
                waitBytesCount = numBytes;
                resolveOnEnoughData = resolve;
            });
        }
    }

    function append(data:Buffer) {
		if (buffer.length - index >= data.length) {
			data.copy(buffer, index, 0, data.length);
		} else {
			var newSize = (Math.ceil((index + data.length) / BUFFER_SIZE) + 1) * BUFFER_SIZE;
			if (index == 0) {
				buffer = new Buffer(newSize);
				data.copy(buffer, 0, 0, data.length);
			} else {
				buffer = Buffer.concat([buffer.slice(0, index), data], newSize);
			}
		}
		index += data.length;
        checkWaiter();
	}

    function onData(data:Buffer) {
        append(data);
    }

    function checkWaiter() {
        trace('checkWaiter data:${dataLength()} waitBytes:$waitBytesCount hasResolver:${(resolveOnEnoughData != null)}');
        if ((resolveOnEnoughData != null) && (dataLength() >= waitBytesCount)) {
            var resolve = resolveOnEnoughData;
            resolveOnEnoughData = null;
            waitBytesCount = 0;
            resolve(dataLength());
        }
    }

    function dataLength() {
        return index - readIndex;
    }
}

typedef PendingCommand = {command:Command, callback:Message -> Void, errorBack:Message -> Void};

@:access(debugger.HaxeProtocol)
class Connection extends EventEmitter<Connection> {

    public static var EVENT_CONNECTED:Event<Void -> Void> = "EVENT_CONNECTED";
    public static var INFO_MESSAGE:Event<Message -> Void> = "EVENT_INFO";

    var socket:Socket;
    var output:SocketOutStream;
    var input:SocketInStream;
    var isEstablished:Bool;
	var index:Int;
    var pendingCommands:List<PendingCommand>;

    function new(socket:Socket) {
        super();
        this.socket = socket;
        output = new SocketOutStream(socket);
        input = new SocketInStream(socket);
        pendingCommands = new List<PendingCommand>();
    }

    public function handShake():Promise<Int> {
        HaxeProtocol.writeServerIdentification(output);
        return input.waitForData(HaxeProtocol.gClientIdentification.length)
            .then(function(numBytes:Int):Promise<Int> {
                HaxeProtocol.readClientIdentification(input);
                trace("Connection istablished");
                isEstablished = true;
                return Promise.resolve(0);
            })
            .catchError(function(e:Dynamic) {
                trace("Client version not supported.");
                trace(e);
                socket.end();
                return Promise.reject(e);
            });
    }

    public function start() {
        waitOutputLoop();
    }

    function waitOutputLoop() {
        trace("waitOutputLoop");
        var messageLength = 0;
        input.waitForData(8)
            .then(function(_) {
                messageLength = calcMessageLength();
                trace('waiting message length: $messageLength');
                return input.waitForData(messageLength);
            })
            .then(function(_) {
                var messageSerial = input.read(messageLength);
                var raw = haxe.Unserializer.run(messageSerial.toString());
                try {
                     var message = cast(raw, Message);
                     onMessage(message);
                }
                catch (e : Dynamic) {
                    throw "Expected Message, but got " + raw + ": " + e;
                }
                trace("!!!");
                haxe.Timer.delay(waitOutputLoop, 0);
            });
    }

    function onMessage(message:Message) {
        trace('Message got: $message');
        if (isResponse(message)) {
            var command = pendingCommands.pop();
            command.callback(message);
        }
        else {
            trace('emit message: $message');
            emit(INFO_MESSAGE, message);
        }
    }

    function calcMessageLength():Int {
        var msg_len_raw = input.read(8);

        // Convert to number
        var msg_len : Int = 0;
        for (i in 0 ... 8) {
            msg_len *= 10;
            msg_len += msg_len_raw.get(i) - 48; // 48 is ASCII '0'
        }
        return msg_len;
    }

    public function sendCommand(command:Command):Promise<Message> {
        trace('sendCommand: $command');
        return new Promise<Message>(function(resolve, reject){
            pendingCommands.add({command:command, callback:resolve, errorBack:reject});
            HaxeProtocol.writeCommand(output, command);
        });
    }

    public static function create(socket:Socket):Promise<Connection> {
        var connection = new Connection(socket);
        return connection.handShake()
            .then(function(_) {
                return connection;
            });
    }

    function isResponse(message):Bool {
        return switch(message) {
            case ThreadCreated(_) | ThreadTerminated(_) | ThreadStarted(_), ThreadStopped(_):
                false;
            default:
                true;
        }
    }
}