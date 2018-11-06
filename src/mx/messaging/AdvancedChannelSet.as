package mx.messaging
{
   import flash.events.ErrorEvent;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.NetStatusEvent;
   import flash.events.TimerEvent;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   import flash.utils.getTimer;
   import mx.logging.ILogger;
   import mx.logging.Log;
   import mx.messaging.config.ServerConfig;
   import mx.messaging.events.ChannelEvent;
   import mx.messaging.events.ChannelFaultEvent;
   import mx.messaging.events.MessageAckEvent;
   import mx.messaging.events.MessageEvent;
   import mx.messaging.events.MessageFaultEvent;
   import mx.messaging.messages.AcknowledgeMessage;
   import mx.messaging.messages.AsyncMessage;
   import mx.messaging.messages.CommandMessage;
   import mx.messaging.messages.ErrorMessage;
   import mx.messaging.messages.IMessage;
   import mx.messaging.messages.ReliabilityMessage;
   import mx.resources.ResourceManager;
   import mx.rpc.AsyncDispatcher;
   
   [ResourceBundle("data")]
   public class AdvancedChannelSet extends ChannelSet
   {
      
      public static const ONE_SECOND_MILLIS:int = 1000;
      
      public static const MAX_REPLY_FETCH_INTERVAL_MILLIS:int = 30000;
      
      public static const START:String = "start";
      
      public static const STOP:String = "stop";
      
      public static const RATE_SEPERATOR:String = "_;_";
      
      protected static const ADAPTIVE_FREQUENCY_DESTINATION:String = "_DSAF";
      
      private static const ADAPTIVE_FREQUENCY_HEADER:String = "DSAdaptiveFrequency";
      
      private static const CLOSE_DUE_TO_CONNECTION_FAILURE:int = 0;
      
      private static const CLOSE_DUE_TO_RESET:int = 1;
      
      private static const CLOSE_DUE_TO_EXPLICIT_DISCONNECT:int = 2;
      
      private static const FETCH_PENDING_REPLY_HEADER:String = "DSFetchPendingReply";
      
      private static var _reliableReconnectDuration:int = 0;
       
      
      protected var _producer:Producer;
      
      private var _adaptiveMessages:int;
      
      private var _adaptiveStartTime:Number = 0;
      
      private var _connectableDestination:String;
      
      private var _connectMsg:CommandMessage;
      
      private var _fillTail:Boolean;
      
      private var _handshaking:Boolean;
      
      private var _inQueue:Array;
      
      private var _inSequenceNumber:int;
      
      private var _log:ILogger;
      
      private var _mostRecentChannelFaultEvent:ChannelFaultEvent;
      
      private var _outQueue:Array;
      
      private var _outSequenceNumber:int;
      
      private var _outstandingMessages:Object;
      
      private var _pendingReliableReplies:Array;
      
      private var _pendingReplyFetchTimer:Timer;
      
      private var _pendingReliableSends:Array;
      
      private var _pendingReliableMessages:Dictionary;
      
      private var _reliableAckBarrier:Boolean;
      
      private var _reliableProxyAgents:Dictionary;
      
      private var _reliableProxyAgentCount:int;
      
      private var _reliableDestinationLookup:Object;
      
      private var _reliableDestinationCount:int;
      
      private var _reliableReconnectTimer:Timer;
      
      private var _repairingSequence:Boolean;
      
      private var _sendBarrier:Boolean;
      
      private var _sendReliableAck:Boolean;
      
      private var _selectiveReliableAck:Array;
      
      private var _sequenceId:String;
      
      private var _shouldBeConnected:Boolean;
      
      private var _reliableReconnectDuration:int;
      
      public function AdvancedChannelSet(channelIds:Array = null, clusteredWithURLLoadBalancing:Boolean = false)
      {
         this._producer = new Producer();
         this._log = Log.getLogger("mx.messaging.AdvancedChannelSet");
         this._outstandingMessages = {};
         this._pendingReliableReplies = [];
         this._pendingReliableSends = [];
         this._pendingReliableMessages = new Dictionary();
         this._reliableReconnectDuration = AdvancedChannelSet.reliableReconnectDuration;
         super(channelIds,clusteredWithURLLoadBalancing);
         this._producer.addEventListener(MessageAckEvent.ACKNOWLEDGE,this.producerAckHandler);
         this._producer.addEventListener(MessageFaultEvent.FAULT,this.producerFaultHandler);
         this._producer.setClientId("DSAdvMsg");
         this._producer.id = "DSAdvMsg";
         this._connectMsg = new CommandMessage();
         this._connectMsg.messageId = "trigger-connect";
         this._connectMsg.operation = CommandMessage.TRIGGER_CONNECT_OPERATION;
      }
      
      public static function get reliableReconnectDuration() : int
      {
         return _reliableReconnectDuration;
      }
      
      public static function set reliableReconnectDuration(value:int) : void
      {
         if(value < 0)
         {
            throw new RangeError(ResourceManager.getInstance().getString("data","invalidReliableReconnectDuration"));
         }
         _reliableReconnectDuration = value;
      }
      
      public function get reliableReconnectDuration() : int
      {
         return this._reliableReconnectDuration;
      }
      
      public function set reliableReconnectDuration(value:int) : void
      {
         if(value < 0)
         {
            throw new RangeError(ResourceManager.getInstance().getString("data","invalidReliableReconnectDuration"));
         }
         this._reliableReconnectDuration = value;
      }
      
      override public function channelConnectHandler(event:ChannelEvent) : void
      {
         var sendTuple:Array = null;
         this._reliableDestinationLookup = {};
         this._reliableDestinationCount = 0;
         var destinations:XMLList = ServerConfig.xml..destination;
         var n:int = destinations.length();
         for(var i:int = 0; i < n; i++)
         {
            this.registerDestinationReliability(destinations[i].@id,destinations[i].properties.network.reliable == true);
         }
         this._producer.channelConnectHandler(event);
         if(this._sequenceId != null)
         {
            this.reliableHandshake();
         }
         this._sendBarrier = true;
         super.channelConnectHandler(event);
         this._sendBarrier = false;
         var snapshot:Array = this._pendingReliableSends.slice();
         while(snapshot.length > 0)
         {
            sendTuple = snapshot.shift();
            this._pendingReliableSends.shift();
            delete this._pendingReliableMessages[sendTuple[1]];
            this.send(sendTuple[0],sendTuple[1]);
         }
      }
      
      override public function channelDisconnectHandler(event:ChannelEvent) : void
      {
         if(this._sequenceId != null)
         {
            if(connected && !this._repairingSequence && this._shouldBeConnected && !event.rejected)
            {
               this.repairSequence(event);
            }
            else if(this._reliableReconnectTimer == null && event.channel.reliableReconnectDuration == -1)
            {
               this._repairingSequence = false;
               super.channelDisconnectHandler(event);
               this.closeSequence();
            }
            else if(Log.isDebug())
            {
               this._log.debug("Ignoring ChannelEvent.DISCONNECT; reliable reconnect attempt pending.");
            }
         }
         else
         {
            super.channelDisconnectHandler(event);
         }
      }
      
      override public function channelFaultHandler(event:ChannelFaultEvent) : void
      {
         if(this._sequenceId != null && !event.connected)
         {
            if(connected && !this._repairingSequence && this._shouldBeConnected && !event.rejected)
            {
               this._mostRecentChannelFaultEvent = event;
               this.repairSequence(event);
            }
            else if(this._reliableReconnectTimer == null && event.channel.reliableReconnectDuration == -1)
            {
               this._repairingSequence = false;
               super.channelFaultHandler(event);
               this.closeSequence();
            }
            else if(Log.isDebug())
            {
               this._log.debug("Ignoring ChannelFaultEvent; reliable reconnect attempt pending.");
            }
         }
         else
         {
            super.channelFaultHandler(event);
         }
      }
      
      override public function disconnect(agent:MessageAgent) : void
      {
         var proxyAgent:ReliableProxyAgent = null;
         if(!(agent is ReliableProxyAgent) && this._reliableProxyAgents != null)
         {
            proxyAgent = this._reliableProxyAgents[agent];
            if(proxyAgent != null)
            {
               delete this._reliableProxyAgents[agent];
               this._reliableProxyAgentCount--;
               super.disconnect(proxyAgent);
            }
         }
         super.disconnect(agent);
         if(messageAgents.length == 1 && messageAgents[0] == this._producer)
         {
            this._shouldBeConnected = false;
            this._producer.disconnect();
            this.closeSequence(CLOSE_DUE_TO_EXPLICIT_DISCONNECT);
         }
      }
      
      override public function send(agent:MessageAgent, message:IMessage) : void
      {
         if(connected && !this._repairingSequence)
         {
            if(this._sendBarrier)
            {
               this.queuePendingReliableMessage(agent,message);
               return;
            }
            if(this.isDestinationReliable(agent.destination) && !(message is CommandMessage && (message as CommandMessage).operation == CommandMessage.TRIGGER_CONNECT_OPERATION))
            {
               if(this._sequenceId != null && !this._handshaking)
               {
                  this.processReliableSend(agent,message);
               }
               else
               {
                  this.queuePendingReliableMessage(agent,message);
                  this.reliableHandshake();
               }
            }
            else
            {
               this.superSend(agent,message);
            }
         }
         else
         {
            this.queuePendingReliableMessage(agent,message);
            if(!this._repairingSequence)
            {
               this._connectableDestination = message.destination;
               this.triggerConnect();
            }
         }
      }
      
      override protected function faultPendingSends(event:ChannelEvent) : void
      {
         var tupleToRemove:Array = null;
         var msg:IMessage = null;
         var errMsg:ErrorMessage = null;
         super.faultPendingSends(event);
         while(this._pendingReliableSends.length > 0)
         {
            tupleToRemove = this._pendingReliableSends.shift();
            msg = tupleToRemove[1] as IMessage;
            delete this._pendingReliableMessages[msg];
            if(msg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] != null)
            {
               delete msg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
            }
            errMsg = this.generateErrorMessageForReliableMessage(msg.messageId,CLOSE_DUE_TO_CONNECTION_FAILURE,event);
            (tupleToRemove[0] as MessageAgent).fault(errMsg,msg);
         }
      }
      
      override protected function messageHandler(event:MessageEvent) : void
      {
         var seqId:String = event.message.headers[ReliabilityMessage.SEQUENCE_ID_HEADER];
         if(seqId != null && seqId != this._sequenceId)
         {
            return;
         }
         if(event.message.headers[ReliabilityMessage.REQUEST_ACK_HEADER] && this._sequenceId != null)
         {
            this.sendReliableAck(true);
         }
         this.handleAdaptiveFrequency(event);
         if(event.message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] != null)
         {
            this.registerDestinationReliability(event.message.destination,true);
         }
         if(this.isDestinationReliable(event.message.destination))
         {
            unscheduleHeartbeat();
            this.processReliableReceive(event);
            scheduleHeartbeat();
         }
         else
         {
            super.messageHandler(event);
         }
      }
      
      protected function handleAdaptiveFrequency(event:MessageEvent) : void
      {
         var index:int = 0;
         var rateString:String = null;
         var serverSendRate:Number = NaN;
         var intervalSeconds:Number = NaN;
         var messageReceiveRate:Number = NaN;
         if(this._adaptiveStartTime != 0)
         {
            this._adaptiveMessages++;
         }
         var value:String = event.message.headers[ADAPTIVE_FREQUENCY_HEADER];
         if(value != null)
         {
            if(value.indexOf(START) == 0)
            {
               if(Log.isDebug())
               {
                  this._log.debug("AdvancedChannelSet started measuring its message receive rate.");
               }
               this._adaptiveStartTime = getTimer();
               this._adaptiveMessages = 1;
            }
            else if(value.indexOf(STOP) == 0)
            {
               index = value.indexOf(RATE_SEPERATOR);
               rateString = value.substr(index + RATE_SEPERATOR.length);
               serverSendRate = Number(rateString);
               intervalSeconds = (getTimer() - this._adaptiveStartTime) / ONE_SECOND_MILLIS;
               messageReceiveRate = this._adaptiveMessages / intervalSeconds;
               this.reportMessageRateDifference(serverSendRate,messageReceiveRate);
            }
         }
      }
      
      protected function reportMessageRateDifference(serverSendRate:Number, messageReceiveRate:Number) : void
      {
         var ack:AcknowledgeMessage = null;
         if(Log.isDebug())
         {
            this._log.debug("AdvancedChannelSet message receive rate for the window is " + messageReceiveRate.toFixed(2) + " while server send rate is " + serverSendRate + ".");
         }
         var diff:int = int(Math.round(serverSendRate - messageReceiveRate));
         if(diff >= 1)
         {
            if(Log.isDebug())
            {
               this._log.debug("AdvancedChannel is reporting rate difference of " + diff + " to the server.");
            }
            ack = new AcknowledgeMessage();
            ack.body = diff.toFixed(0);
            ack.clientId = this._producer.clientId;
            ack.destination = ADAPTIVE_FREQUENCY_DESTINATION;
            this.superSend(this._producer,ack);
         }
         this._adaptiveStartTime = 0;
      }
      
      override protected function sendHeartbeatHandler(event:TimerEvent) : void
      {
         unscheduleHeartbeat();
         if(connected && !this._repairingSequence && currentChannel != null)
         {
            sendHeartbeat();
            scheduleHeartbeat();
         }
      }
      
      protected function superSend(agent:MessageAgent, message:IMessage) : void
      {
         this.setAckHeader(message);
         super.send(agent,message);
      }
      
      private function ackReliableRequestTuple(sequenceNumber:String) : Array
      {
         var n:int = this._outQueue.length;
         for(var i:int = 0; i < n; i++)
         {
            if(this._outQueue[i][0] == sequenceNumber)
            {
               if(Log.isDebug())
               {
                  this._log.debug("Acknowledgement for reliable sent message \'{0}\' received.",sequenceNumber);
               }
               return this._outQueue.splice(i,1)[0];
            }
         }
         return null;
      }
      
      private function addToInQueue(tuple:Array) : Boolean
      {
         var probeSeqNum:int = 0;
         var seqNum:int = tuple[0];
         if(this.processInboundSequenceNumber(seqNum))
         {
            if(Log.isDebug())
            {
               this._log.debug("Adding received message with sequence number \'{0}\' to the reliable inbound queue.",seqNum);
            }
            this._sendReliableAck = true;
            var n:int = this._inQueue.length;
            if(n > 0)
            {
               while(--n >= 0)
               {
                  probeSeqNum = this._inQueue[n][0];
                  if(seqNum > probeSeqNum)
                  {
                     this._inQueue.splice(n + 1,0,tuple);
                     return true;
                  }
               }
               this._inQueue.unshift(tuple);
            }
            else
            {
               this._inQueue.push(tuple);
            }
            return true;
         }
         if(Log.isDebug())
         {
            this._log.debug("Ignoring received message with sequence number \'{0}\'; duplicate delivery.",seqNum);
         }
         return false;
      }
      
      private function cleanupPendingReplies(request:IMessage) : void
      {
         var n:int = this._pendingReliableReplies.length;
         for(var i:int = 0; i < n; i++)
         {
            if(this._pendingReliableReplies[i][1] == request)
            {
               this._pendingReliableReplies.splice(i,1);
               break;
            }
         }
         if(this._pendingReliableReplies.length == 0 && this._pendingReplyFetchTimer != null)
         {
            this.cleanupPendingReplyTimer();
         }
      }
      
      private function cleanupPendingReplyTimer() : void
      {
         if(this._pendingReplyFetchTimer != null)
         {
            this._pendingReplyFetchTimer.stop();
            this._pendingReplyFetchTimer.removeEventListener(TimerEvent.TIMER,this.fetchPendingReplies);
            this._pendingReplyFetchTimer = null;
         }
      }
      
      private function closeSequence(reason:int = 0) : void
      {
         var tupleToRemove:Array = null;
         var msg:IMessage = null;
         var errMsg:ErrorMessage = null;
         var n:int = 0;
         var i:int = 0;
         var proxyAgent:ReliableProxyAgent = null;
         var disconnectEvent:ChannelEvent = null;
         var connectEvent:ChannelEvent = null;
         if(Log.isDebug() && this._sequenceId != null)
         {
            this._log.debug("Shutting down current reliable messaging sequence with id: " + this._sequenceId);
         }
         this._repairingSequence = false;
         this.shutdownReliableReconnect();
         while(this._pendingReliableSends.length > 0)
         {
            tupleToRemove = this._pendingReliableSends.shift();
            msg = tupleToRemove[1] as IMessage;
            delete this._pendingReliableMessages[msg];
            if(msg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] != null)
            {
               delete msg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
            }
            errMsg = this.generateErrorMessageForReliableMessage(msg.messageId,reason);
            (tupleToRemove[0] as MessageAgent).fault(errMsg,msg);
         }
         if(this._outQueue != null)
         {
            n = this._outQueue.length;
            for(i = 0; i < n; i++)
            {
               tupleToRemove = this._outQueue[i];
               msg = tupleToRemove[1] as IMessage;
               proxyAgent = tupleToRemove[2] as ReliableProxyAgent;
               errMsg = this.generateErrorMessageForReliableMessage(msg.messageId,reason);
               proxyAgent.targetAgent.fault(errMsg,msg);
            }
         }
         if(this._reliableProxyAgents != null)
         {
            disconnectEvent = ChannelEvent.createEvent(ChannelEvent.DISCONNECT,currentChannel,true,false,false);
            connectEvent = ChannelEvent.createEvent(ChannelEvent.CONNECT,currentChannel,false,false,true);
            for each(proxyAgent in this._reliableProxyAgents)
            {
               if(reason == CLOSE_DUE_TO_RESET && proxyAgent.targetAgent is Consumer && (proxyAgent.targetAgent as Consumer).subscribed)
               {
                  proxyAgent.targetAgent.channelDisconnectHandler(disconnectEvent);
                  proxyAgent.targetAgent.channelConnectHandler(connectEvent);
               }
               proxyAgent.disconnect();
            }
         }
         this._handshaking = false;
         this._sequenceId = null;
         this._inQueue = null;
         this._inSequenceNumber = 0;
         this._outQueue = null;
         this._outSequenceNumber = 0;
         this._reliableAckBarrier = false;
         this._reliableProxyAgents = null;
         this._reliableProxyAgentCount = 0;
         this._mostRecentChannelFaultEvent = null;
         this._shouldBeConnected = false;
         this._selectiveReliableAck = null;
         this._pendingReliableReplies = [];
         this.cleanupPendingReplyTimer();
      }
      
      private function fetchPendingReplies(event:TimerEvent) : void
      {
         var tuple:Array = null;
         for each(tuple in this._pendingReliableReplies)
         {
            (tuple[1] as IMessage).headers[FETCH_PENDING_REPLY_HEADER] = true;
            this.send(tuple[0],tuple[1]);
         }
      }
      
      private function handlePendingReply(requestId:String) : void
      {
         var tuple:Array = null;
         var i:int = 0;
         var req:IMessage = null;
         var newDelay:int = 0;
         var registered:Boolean = false;
         for each(tuple in this._pendingReliableReplies)
         {
            if((tuple[1] as IMessage).messageId == requestId)
            {
               registered = true;
               break;
            }
         }
         if(!registered)
         {
            for(i = this._outQueue.length - 1; i >= 0; i--)
            {
               req = this._outQueue[i][1] as IMessage;
               if(req.messageId == requestId)
               {
                  this._pendingReliableReplies.push([(this._outQueue[i][2] as ReliableProxyAgent).targetAgent,req]);
               }
            }
         }
         if(this._pendingReplyFetchTimer == null)
         {
            this._pendingReplyFetchTimer = new Timer(ONE_SECOND_MILLIS,1);
            this._pendingReplyFetchTimer.addEventListener(TimerEvent.TIMER,this.fetchPendingReplies);
            this._pendingReplyFetchTimer.start();
         }
         else if(!this._pendingReplyFetchTimer.running)
         {
            newDelay = this._pendingReplyFetchTimer.delay << 2;
            if(newDelay > MAX_REPLY_FETCH_INTERVAL_MILLIS)
            {
               newDelay = MAX_REPLY_FETCH_INTERVAL_MILLIS;
            }
            this._pendingReplyFetchTimer.delay = newDelay;
            this._pendingReplyFetchTimer.repeatCount = 1;
            this._pendingReplyFetchTimer.start();
         }
      }
      
      private function isDestinationReliable(id:String) : Boolean
      {
         if(this._reliableDestinationLookup.hasOwnProperty(id))
         {
            return this._reliableDestinationLookup[id];
         }
         if(ServerConfig.xml..destination.(@id == id).network.reliable == true)
         {
            this._reliableDestinationCount++;
            this._reliableDestinationLookup[id] = true;
            return true;
         }
         this._reliableDestinationLookup[id] = false;
         return false;
      }
      
      private function generateErrorMessageForReliableMessage(reliableMessageId:String, reason:int, rootCause:Object = null) : ErrorMessage
      {
         var errMsg:ErrorMessage = new ErrorMessage();
         errMsg.faultCode = "Client.Error.MessageSend";
         errMsg.faultString = "Could not send message reliably.";
         switch(reason)
         {
            case CLOSE_DUE_TO_CONNECTION_FAILURE:
               errMsg.headers[ErrorMessage.RETRYABLE_HINT_HEADER] = true;
               errMsg.faultDetail = "Failed to negotiate a reliable messaging sequence with remote host.";
               break;
            case CLOSE_DUE_TO_RESET:
               errMsg.faultDetail = "Existing reliable sequence was reset to a new sequence upon reconnect to remote host.";
               break;
            case CLOSE_DUE_TO_EXPLICIT_DISCONNECT:
               errMsg.faultDetail = "Client initiated disconnect.";
         }
         errMsg.correlationId = reliableMessageId;
         if(reason == CLOSE_DUE_TO_CONNECTION_FAILURE)
         {
            if(rootCause == null)
            {
               rootCause = this._mostRecentChannelFaultEvent;
            }
            if(rootCause is ChannelFaultEvent)
            {
               errMsg.faultDetail = rootCause.faultCode + " " + rootCause.faultString + " " + rootCause.faultDetail;
            }
            errMsg.rootCause = rootCause;
         }
         return errMsg;
      }
      
      private function openSequence(id:String) : void
      {
         if(Log.isDebug())
         {
            this._log.debug("Opening a new reliable messaging sequence with id: " + id);
         }
         this._sequenceId = id;
         this._inQueue = [];
         this._inSequenceNumber = 0;
         this._outQueue = [];
         this._outSequenceNumber = 0;
         this._reliableProxyAgents = new Dictionary();
         this._reliableProxyAgentCount = 0;
      }
      
      private function processInboundSequenceNumber(seqNum:int) : Boolean
      {
         var i:int = 0;
         var range:Array = null;
         var nextRange:Array = null;
         if(seqNum < 0)
         {
            return false;
         }
         var processed:Boolean = false;
         var newGap:Boolean = false;
         if(this._selectiveReliableAck != null)
         {
            for(i = 0; i < this._selectiveReliableAck.length; )
            {
               range = this._selectiveReliableAck[i];
               if(range[0] <= seqNum && seqNum <= range[1])
               {
                  break;
               }
               nextRange = i + 1 < this._selectiveReliableAck.length?this._selectiveReliableAck[i + 1]:null;
               if(nextRange != null)
               {
                  if(nextRange[0] <= seqNum)
                  {
                     i++;
                     continue;
                  }
                  if(range[1] + 1 == seqNum)
                  {
                     range[1]++;
                  }
                  else if(nextRange[0] - 1 == seqNum)
                  {
                     nextRange[0]--;
                  }
                  else
                  {
                     this._selectiveReliableAck.splice(i + 1,0,[seqNum,seqNum]);
                     newGap = true;
                  }
                  if(range[1] + 1 == nextRange[0])
                  {
                     range[1] = nextRange[1];
                     this._selectiveReliableAck.splice(i + 1,1);
                  }
                  processed = true;
                  break;
               }
               if(range[1] + 1 == seqNum)
               {
                  range[1]++;
               }
               else
               {
                  this._selectiveReliableAck.push([seqNum,seqNum]);
                  newGap = true;
               }
               processed = true;
               break;
            }
         }
         else if(this._selectiveReliableAck == null && seqNum == 0)
         {
            this._selectiveReliableAck = [[0,0]];
            processed = true;
         }
         if(newGap)
         {
            if(Log.isDebug())
            {
               this._log.debug("Detected gap in sequence. Sending an ack to the remote host to fill the gap.");
            }
            this.sendReliableAck(false);
         }
         return processed;
      }
      
      private function processInQueue() : void
      {
         var tuple:Array = null;
         var msg:IMessage = null;
         var proxyAgent:ReliableProxyAgent = null;
         var reply:IMessage = null;
         var request:IMessage = null;
         while(this._inQueue != null && this._inQueue.length > 0 && this._inQueue[0][0] == this._inSequenceNumber)
         {
            if(++this._inSequenceNumber == int.MAX_VALUE)
            {
               this._inSequenceNumber = 0;
            }
            tuple = this._inQueue.shift();
            if(tuple.length == 2 && tuple[1] is MessageEvent)
            {
               msg = (tuple[1] as MessageEvent).message;
               delete msg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
               delete msg.headers[ReliabilityMessage.ACK_HEADER];
               if(Log.isDebug())
               {
                  this._log.debug("Processing reliable pushed message with sequence number: " + tuple[0]);
               }
               super.messageHandler(tuple[1]);
            }
            else
            {
               proxyAgent = tuple[3] as ReliableProxyAgent;
               reply = tuple[1] as IMessage;
               delete reply.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
               delete reply.headers[ReliabilityMessage.ACK_HEADER];
               request = tuple[2] as IMessage;
               delete request.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
               delete request.headers[ReliabilityMessage.ACK_HEADER];
               if(Log.isDebug())
               {
                  this._log.debug("Processing reliable reply message with sequence number: " + tuple[0]);
               }
               if(tuple[1] is AcknowledgeMessage)
               {
                  proxyAgent.proxyAcknowledge(tuple[1] as AcknowledgeMessage,tuple[2] as IMessage);
               }
               else
               {
                  proxyAgent.proxyFault(tuple[1] as ErrorMessage,tuple[2] as IMessage);
               }
            }
         }
      }
      
      private function processReliableBatch(batch:Array) : void
      {
         var message:AsyncMessage = null;
         var seqNums:Array = null;
         var m:AsyncMessage = null;
         var requestTuple:Array = null;
         if(Log.isDebug() && batch.length > 0)
         {
            seqNums = [];
            for each(m in batch)
            {
               seqNums.push(m.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER]);
            }
            this._log.debug("Received batch of {0} reliable messages. Sequence numbers: {1}",batch.length,seqNums);
         }
         for each(message in batch)
         {
            if(message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] == null)
            {
               if(Log.isDebug())
               {
                  this._log.debug("Received a batch message lacking a reliable sequence number: " + message);
               }
            }
            else if(message is AcknowledgeMessage)
            {
               requestTuple = this.ackReliableRequestTuple(message.headers[ReliabilityMessage.ACK_HEADER]);
               delete message.headers[ReliabilityMessage.ACK_HEADER];
               if(requestTuple != null)
               {
                  this.processReliableReply(message as AcknowledgeMessage,requestTuple[1],requestTuple[2]);
               }
               else if(Log.isWarn())
               {
                  this._log.warn("Received a reply message within a reliable message batch that had no corresponding request message: " + message);
               }
            }
            else if(message is AsyncMessage)
            {
               this.processReliableReceive(MessageEvent.createEvent(MessageEvent.MESSAGE,message));
            }
            else if(Log.isError())
            {
               this._log.error("Received an unsupported message within a reliable message batch: " + message);
            }
         }
      }
      
      private function processReliableReceive(event:MessageEvent) : void
      {
         var seqNum:int = event.message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
         if(this._sequenceId != null)
         {
            this.addToInQueue([seqNum,event]);
            this.processInQueue();
         }
         else if(Log.isDebug())
         {
            this._log.debug("Ignoring reliable receive with sequence number \'{0}\' because the sequence has been closed.",seqNum);
         }
      }
      
      function processReliableReply(ackMsg:AcknowledgeMessage, msg:IMessage, agent:ReliableProxyAgent) : void
      {
         var rootCause:Object = null;
         if(ackMsg.headers[ReliabilityMessage.REPLY_PENDING_HEADER] != null)
         {
            this.handlePendingReply(ackMsg.headers[ReliabilityMessage.REPLY_PENDING_HEADER]);
         }
         if(ackMsg.headers[ReliabilityMessage.BATCH_HEADER] == true)
         {
            if(ackMsg.headers[ReliabilityMessage.REPLY_PENDING_HEADER] != null)
            {
               this.handlePendingReply(ackMsg.headers[ReliabilityMessage.REPLY_PENDING_HEADER]);
            }
            this.processReliableBatch(ackMsg.body as Array);
            return;
         }
         if(ackMsg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] == null)
         {
            return;
         }
         var seqNum:int = ackMsg.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
         if(this._sequenceId != null)
         {
            if(ackMsg is ErrorMessage)
            {
               rootCause = (ackMsg as ErrorMessage).rootCause;
               if(rootCause is ChannelEvent || rootCause is ChannelFaultEvent || (rootCause is ErrorEvent || rootCause is IOErrorEvent) || (rootCause is NetStatusEvent || rootCause is Object && rootCause.level == "error"))
               {
                  if(Log.isDebug())
                  {
                     this._log.debug("Received an error for a reliable request but a resend will be attempted. Error root cause: " + rootCause);
                  }
                  this.resendReliableMessage(msg,rootCause);
                  return;
               }
            }
            if(ackMsg.headers[ReliabilityMessage.ACK_HEADER] != null)
            {
               this.ackReliableRequestTuple(ackMsg.headers[ReliabilityMessage.ACK_HEADER]);
            }
            if(this.addToInQueue([seqNum,ackMsg,msg,agent]))
            {
               this.cleanupPendingReplies(msg);
               this.processInQueue();
            }
         }
         else if(Log.isDebug())
         {
            this._log.debug("Ignoring reliable reply with sequence number \'{0}\' because the sequence has been closed.",seqNum);
         }
      }
      
      private function processReliableSend(agent:MessageAgent, message:IMessage) : void
      {
         var seqNum:int = -1;
         if(message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] != null)
         {
            seqNum = message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
         }
         else
         {
            seqNum = this._outSequenceNumber;
            if(++this._outSequenceNumber == int.MAX_VALUE)
            {
               this._outSequenceNumber = 0;
            }
            message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER] = seqNum;
            message.headers[ReliabilityMessage.SEQUENCE_ID_HEADER] = this._sequenceId;
         }
         var proxyAgent:ReliableProxyAgent = this._reliableProxyAgents[agent];
         if(proxyAgent == null)
         {
            if(Log.isDebug())
            {
               this._log.debug("Creating ReliableProxyAgent for MessageAgent \'{0}\'.",agent.id);
            }
            proxyAgent = new ReliableProxyAgent(agent);
            proxyAgent.channelSet = this;
            this._reliableProxyAgents[agent] = proxyAgent;
            this._reliableProxyAgentCount++;
         }
         if(message.headers[FETCH_PENDING_REPLY_HEADER] == true)
         {
            if(Log.isDebug())
            {
               this._log.debug("Attempting to fetch pending reply for message with sequence number \'{0}\'.",seqNum);
            }
            delete message.headers[FETCH_PENDING_REPLY_HEADER];
         }
         else
         {
            if(Log.isDebug())
            {
               this._log.debug("Adding reliable send message with sequence number \'{0}\' to the reliable outbound queue.",seqNum);
            }
            this._outQueue.push([seqNum,message,proxyAgent]);
         }
         this.superSend(proxyAgent,message);
      }
      
      private function producerAckHandler(event:MessageAckEvent) : void
      {
         var handlers:Array = null;
         if(!event.message.headers[AcknowledgeMessage.ERROR_HINT_HEADER])
         {
            handlers = this._outstandingMessages[AcknowledgeMessage(event.message).correlationId];
            if(handlers != null)
            {
               delete this._outstandingMessages[AcknowledgeMessage(event.message).correlationId];
               handlers[0](event);
            }
            else if(Log.isInfo())
            {
               this._log.info("No ack callback registered for internal message with id: " + AcknowledgeMessage(event.message).correlationId);
            }
         }
      }
      
      private function producerFaultHandler(event:MessageFaultEvent) : void
      {
         var handlers:Array = this._outstandingMessages[ErrorMessage(event.message).correlationId];
         if(handlers != null)
         {
            delete this._outstandingMessages[ErrorMessage(event.message).correlationId];
            handlers[1](event);
         }
         else if(Log.isInfo())
         {
            this._log.info("No fault callback registered for internal message with id: " + ErrorMessage(event.message).correlationId);
         }
      }
      
      private function queuePendingReliableMessage(agent:MessageAgent, message:IMessage) : void
      {
         if(this._pendingReliableMessages[message] == null)
         {
            this._pendingReliableMessages[message] = true;
            this._pendingReliableSends.push([agent,message]);
         }
      }
      
      private function reliableAckHandler(event:Event) : void
      {
         var replyMessage:IMessage = null;
         if(Log.isDebug())
         {
            this._log.debug("Explicit reliable sequence ack completed successfully? " + !(event is MessageFaultEvent));
         }
         this._reliableAckBarrier = false;
         if(!(event is MessageFaultEvent) && event is MessageAckEvent)
         {
            replyMessage = (event as MessageAckEvent).message;
            if(replyMessage.body is Array)
            {
               this.processReliableBatch(replyMessage.body as Array);
            }
         }
      }
      
      private function reliableHandshake() : void
      {
         var handshakeMsg:ReliabilityMessage = null;
         var capturedThis:ChannelSet = null;
         if(this._handshaking)
         {
            return;
         }
         if(this.reliableReconnectDuration == 0)
         {
            this.reliableReconnectDuration = ONE_SECOND_MILLIS;
         }
         this._shouldBeConnected = true;
         this._handshaking = true;
         handshakeMsg = new ReliabilityMessage();
         handshakeMsg.destination = ReliabilityMessage.DESTINATION;
         if(this._sequenceId == null)
         {
            handshakeMsg.operation = ReliabilityMessage.CREATE_SEQUENCE_OPERATION;
         }
         else
         {
            handshakeMsg.operation = ReliabilityMessage.RECONNECT_SEQUENCE_OPERATION;
            handshakeMsg.headers[ReliabilityMessage.SEQUENCE_ID_HEADER] = this._sequenceId;
            if(this._selectiveReliableAck != null)
            {
               handshakeMsg.headers[ReliabilityMessage.ACK_HEADER] = this._selectiveReliableAck;
            }
         }
         var handshakeSuccess:Function = function(ackEvent:MessageAckEvent):void
         {
            var sendTuple:Array = null;
            var batch:Array = null;
            _handshaking = false;
            _repairingSequence = false;
            if(handshakeMsg.operation == ReliabilityMessage.CREATE_SEQUENCE_OPERATION)
            {
               openSequence(ackEvent.acknowledgeMessage.body as String);
               if(Log.isDebug())
               {
                  _log.debug("Created new reliable messaging sequence with id: " + (ackEvent.acknowledgeMessage.body as String));
               }
            }
            else if(handshakeMsg.operation == ReliabilityMessage.RECONNECT_SEQUENCE_OPERATION && ackEvent.acknowledgeMessage.body is String)
            {
               if(Log.isDebug())
               {
                  _log.debug("Resetting to a new reliable messaging sequence with id: " + (ackEvent.acknowledgeMessage.body as String));
               }
               closeSequence(CLOSE_DUE_TO_RESET);
               openSequence(ackEvent.acknowledgeMessage.body as String);
            }
            else if(Log.isDebug())
            {
               _log.debug("Reconnected to existing reliable messaging sequence with id: " + _sequenceId);
            }
            while(_pendingReliableSends.length > 0)
            {
               sendTuple = _pendingReliableSends.shift();
               delete _pendingReliableMessages[sendTuple[1]];
               send(sendTuple[0],sendTuple[1]);
            }
            if(handshakeMsg.operation == ReliabilityMessage.RECONNECT_SEQUENCE_OPERATION && ackEvent.acknowledgeMessage.body is Array)
            {
               batch = ackEvent.acknowledgeMessage.body as Array;
               if(batch.length > 0)
               {
                  processReliableBatch(ackEvent.acknowledgeMessage.body as Array);
                  sendReliableAck(false,true);
               }
            }
            scheduleHeartbeat();
         };
         capturedThis = this;
         var handshakeFault:Function = function(event:MessageFaultEvent):void
         {
            if(Log.isError())
            {
               _log.error("Failed to negotiate reliable messaging sequence. Root cause: " + event);
            }
            _handshaking = false;
            closeSequence();
            currentChannel.disconnect(capturedThis);
         };
         if(Log.isDebug())
         {
            this._log.debug("Sending reliable handshake.");
         }
         this.sendInternalMessage(handshakeMsg,handshakeSuccess,handshakeFault);
      }
      
      private function registerDestinationReliability(id:String, reliable:Boolean) : void
      {
         if(this._reliableDestinationLookup.hasOwnProperty(id))
         {
            return;
         }
         if(reliable)
         {
            this._reliableDestinationCount++;
            this._reliableDestinationLookup[id] = true;
         }
         else
         {
            this._reliableDestinationLookup[id] = false;
         }
      }
      
      private function repairSequence(event:ChannelEvent) : void
      {
         var sendTuple:Array = null;
         var proxyAgent:ReliableProxyAgent = null;
         if(Log.isDebug())
         {
            this._log.debug("Attempting to repair reliable messaging sequence with id: " + this._sequenceId);
         }
         this._repairingSequence = true;
         unscheduleHeartbeat();
         while(this._outQueue.length)
         {
            sendTuple = this._outQueue.shift();
            proxyAgent = sendTuple[2] as ReliableProxyAgent;
            this._pendingReliableMessages[sendTuple[1]] = true;
            this._pendingReliableSends.push([proxyAgent.targetAgent,sendTuple[1]]);
            proxyAgent.disconnect();
            delete this._reliableProxyAgents[proxyAgent.targetAgent];
            this._reliableProxyAgentCount--;
         }
         if(!event.reconnecting)
         {
            event.reconnecting = true;
            this._reliableReconnectTimer = new Timer(1,1);
            this._reliableReconnectTimer.addEventListener(TimerEvent.TIMER,this.triggerConnect);
            this._reliableReconnectTimer.start();
         }
      }
      
      private function resendReliableMessage(message:IMessage, rootCause:Object) : void
      {
         var tupleToRemove:Array = null;
         var seqNum:int = message.headers[ReliabilityMessage.SEQUENCE_NUMBER_HEADER];
         var n:int = this._outQueue.length;
         for(var i:int = 0; i < n; i++)
         {
            if(this._outQueue[i][0] == seqNum)
            {
               if(Log.isDebug())
               {
                  this._log.debug("Attempting to resend reliable request with sequence number: " + seqNum);
               }
               tupleToRemove = this._outQueue.splice(i,1)[0];
               new AsyncDispatcher(function():void
               {
                  var errMsg:ErrorMessage = null;
                  var proxyAgent:ReliableProxyAgent = tupleToRemove[2] as ReliableProxyAgent;
                  if(connected)
                  {
                     send(proxyAgent.targetAgent,message);
                  }
                  else
                  {
                     errMsg = generateErrorMessageForReliableMessage(message.messageId,CLOSE_DUE_TO_CONNECTION_FAILURE,rootCause);
                     proxyAgent.targetAgent.fault(errMsg,message);
                  }
               },null,1);
               break;
            }
         }
      }
      
      private function sendInternalMessage(message:IMessage, ackHandler:Function, faultHandler:Function) : void
      {
         this._outstandingMessages[message.messageId] = [ackHandler,faultHandler];
         currentChannel.send(this._producer,message);
      }
      
      private function sendReliableAck(responding:Boolean = true, fillTail:Boolean = false) : void
      {
         if(fillTail)
         {
            this._fillTail = true;
         }
         if(!this._reliableAckBarrier)
         {
            this._reliableAckBarrier = true;
            new AsyncDispatcher(function():void
            {
               if(_repairingSequence)
               {
                  _reliableAckBarrier = false;
                  return;
               }
               _sendReliableAck = true;
               var rAck:ReliabilityMessage = new ReliabilityMessage();
               rAck.destination = ReliabilityMessage.DESTINATION;
               rAck.operation = ReliabilityMessage.SEQUENCE_ACK_OPERATION;
               rAck.headers[ReliabilityMessage.SEQUENCE_ID_HEADER] = _sequenceId;
               setAckHeader(rAck);
               if(_fillTail)
               {
                  _fillTail = false;
                  rAck.headers[ReliabilityMessage.FILL_TAIL_HEADER] = true;
               }
               if(Log.isDebug())
               {
                  if(responding)
                  {
                     _log.debug("Responding to an explicit reliable sequence ack request.");
                  }
                  else
                  {
                     _log.debug("Sending a reliable sequence ack explicitly.");
                  }
               }
               sendInternalMessage(rAck,reliableAckHandler,reliableAckHandler);
            },null,1);
         }
         else if(Log.isDebug())
         {
            this._log.debug("Ignoring request for explicit reliable sequence ack request because an ack request is outstanding.");
         }
      }
      
      private function setAckHeader(message:IMessage) : void
      {
         var ackToString:String = null;
         var range:Array = null;
         if(this._sendReliableAck)
         {
            if(Log.isDebug())
            {
               ackToString = "";
               for each(range in this._selectiveReliableAck)
               {
                  ackToString = ackToString + (" (" + range + ")");
               }
               this._log.debug("Adding a reliable messaging sequence ack to the outbound message:" + ackToString);
            }
            this._sendReliableAck = false;
            message.headers[ReliabilityMessage.ACK_HEADER] = this._selectiveReliableAck;
         }
      }
      
      private function shutdownReliableReconnect() : void
      {
         if(this._reliableReconnectTimer != null)
         {
            this._reliableReconnectTimer.stop();
            this._reliableReconnectTimer.removeEventListener(TimerEvent.TIMER,this.triggerConnect);
            this._reliableReconnectTimer = null;
         }
      }
      
      private function superChannelConnectHandler(event:ChannelEvent) : void
      {
         super.channelConnectHandler(event);
      }
      
      private function triggerConnect(event:TimerEvent = null) : void
      {
         this.shutdownReliableReconnect();
         this._shouldBeConnected = true;
         this._connectMsg.destination = this._connectableDestination;
         this._producer.channelSet = null;
         this._producer.channelSet = this;
         this.superSend(this._producer,this._connectMsg);
      }
   }
}
