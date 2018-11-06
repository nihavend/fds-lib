package mx.messaging.messages
{
   import mx.utils.StringUtil;
   
   [RemoteClass(alias="flex.messaging.messages.ReliabilityMessage")]
   public class ReliabilityMessage extends AsyncMessage
   {
      
      public static const DESTINATION:String = "_DSRM";
      
      public static const SEQUENCE_ID_HEADER:String = "DSSeqId";
      
      public static const SEQUENCE_NUMBER_HEADER:String = "DSSeqNum";
      
      public static const ACK_HEADER:String = "DSSeqAck";
      
      public static const REQUEST_ACK_HEADER:String = "DSReqSeqAck";
      
      public static const BATCH_HEADER:String = "DSSeqBatch";
      
      public static const FILL_TAIL_HEADER:String = "DSSeqFillTail";
      
      public static const REPLY_PENDING_HEADER:String = "DSSeqReplyPending";
      
      public static const CREATE_SEQUENCE_OPERATION:int = 0;
      
      public static const RECONNECT_SEQUENCE_OPERATION:int = 1;
      
      public static const SEQUENCE_ACK_OPERATION:int = 2;
      
      public static const UNKNOWN_OPERATION:int = 1000;
      
      private static const OPERATION_NAMES:Array = ["create","reconnect","ack"];
       
      
      public var operation:int = 1000;
      
      public function ReliabilityMessage()
      {
         super();
      }
      
      public static function getOperationAsString(op:int) : String
      {
         return op < OPERATION_NAMES.length?OPERATION_NAMES[op]:"unknown";
      }
      
      override public function toString() : String
      {
         return StringUtil.substitute("(mx.messaging.messages.ReliabilityMessage)\n  messageId = \'{0}\'\n  operation = {1}\n",messageId,ReliabilityMessage.getOperationAsString(this.operation));
      }
   }
}
