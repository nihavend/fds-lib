package mx.data.messages
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import mx.messaging.messages.AcknowledgeMessage;
   import mx.messaging.messages.IMessage;
   
   [RemoteClass(alias="flex.data.messages.SequencedMessage")]
   public class SequencedMessage extends AcknowledgeMessage
   {
      
      private static const DATA_MESSAGE_FLAG:uint = 1;
      
      private static const DYNAMIC_SIZING_FLAG:uint = 2;
      
      private static const SEQUENCE_ID_FLAG:uint = 4;
      
      private static const SEQUENCE_PROXIES_FLAG:uint = 8;
      
      private static const SEQUENCE_SIZE_FLAG:uint = 16;
       
      
      public var dataMessage:DataMessage;
      
      public var dynamicSizing:int;
      
      public var sequenceId:int;
      
      public var sequenceProxies:Array;
      
      public var sequenceSize:int;
      
      public function SequencedMessage()
      {
         super();
      }
      
      override public function getSmallMessage() : IMessage
      {
         if((this as Object).constructor == SequencedMessage)
         {
            return new SequencedMessageExt(this);
         }
         return null;
      }
      
      override public function readExternal(input:IDataInput) : void
      {
         var flags:uint = 0;
         var reservedPosition:uint = 0;
         var j:uint = 0;
         super.readExternal(input);
         var flagsArray:Array = readFlags(input);
         for(var i:uint = 0; i < flagsArray.length; i++)
         {
            flags = flagsArray[i] as uint;
            reservedPosition = 0;
            if(i == 0)
            {
               if((flags & DATA_MESSAGE_FLAG) != 0)
               {
                  this.dataMessage = input.readObject() as DataMessage;
               }
               if((flags & DYNAMIC_SIZING_FLAG) != 0)
               {
                  this.dynamicSizing = input.readObject() as int;
               }
               if((flags & SEQUENCE_ID_FLAG) != 0)
               {
                  this.sequenceId = input.readObject() as int;
               }
               if((flags & SEQUENCE_PROXIES_FLAG) != 0)
               {
                  this.sequenceProxies = input.readObject() as Array;
               }
               if((flags & SEQUENCE_SIZE_FLAG) != 0)
               {
                  this.sequenceSize = input.readObject() as int;
               }
               reservedPosition = 5;
            }
            if(flags >> reservedPosition != 0)
            {
               for(j = reservedPosition; j < 6; j++)
               {
                  if((flags >> j & 1) != 0)
                  {
                     input.readObject();
                  }
               }
            }
         }
      }
      
      override public function writeExternal(output:IDataOutput) : void
      {
         super.writeExternal(output);
         var flags:uint = 0;
         if(this.dataMessage != null)
         {
            flags = flags | DATA_MESSAGE_FLAG;
         }
         if(this.dynamicSizing != 0)
         {
            flags = flags | DYNAMIC_SIZING_FLAG;
         }
         if(this.sequenceId != 0)
         {
            flags = flags | SEQUENCE_ID_FLAG;
         }
         if(this.sequenceProxies != null)
         {
            flags = flags | SEQUENCE_PROXIES_FLAG;
         }
         if(this.sequenceSize != 0)
         {
            flags = flags | SEQUENCE_SIZE_FLAG;
         }
         output.writeByte(flags);
         if(this.dataMessage != null)
         {
            output.writeObject(this.dataMessage);
         }
         if(this.dynamicSizing != 0)
         {
            output.writeObject(this.dynamicSizing);
         }
         if(this.sequenceId != 0)
         {
            output.writeObject(this.sequenceId);
         }
         if(this.sequenceProxies != null)
         {
            output.writeObject(this.sequenceProxies);
         }
         if(this.sequenceSize != 0)
         {
            output.writeObject(this.sequenceSize);
         }
      }
   }
}
