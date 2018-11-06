package mx.data.messages
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import mx.core.mx_internal;
   import mx.data.ConcreteDataService;
   import mx.data.Metadata;
   import mx.data.utils.Managed;
   import mx.data.utils.SerializationDescriptor;
   import mx.data.utils.SerializationProxy;
   import mx.messaging.messages.AsyncMessage;
   import mx.messaging.messages.IMessage;
   import mx.utils.StringUtil;
   
   [RemoteClass(alias="flex.data.messages.DataMessage")]
   public class DataMessage extends AsyncMessage
   {
      
      private static const IDENTITY_FLAG:uint = 1;
      
      private static const OPERATION_FLAG:uint = 2;
      
      public static const CREATE_OPERATION:uint = 0;
      
      public static const FILL_OPERATION:uint = 1;
      
      public static const GET_OPERATION:uint = 2;
      
      public static const UPDATE_OPERATION:uint = 3;
      
      public static const DELETE_OPERATION:uint = 4;
      
      public static const BATCHED_OPERATION:uint = 5;
      
      public static const MULTI_BATCH_OPERATION:uint = 6;
      
      public static const TRANSACTED_OPERATION:uint = 7;
      
      public static const PAGE_OPERATION:uint = 8;
      
      public static const COUNT_OPERATION:uint = 9;
      
      public static const GET_OR_CREATE_OPERATION:uint = 10;
      
      public static const CREATE_AND_SEQUENCE_OPERATION:uint = 11;
      
      public static const GET_SEQUENCE_ID_OPERATION:uint = 12;
      
      public static const SYNCHRONIZE_FILL_OPERATION:uint = 13;
      
      public static const FILLIDS_OPERATION:uint = 15;
      
      public static const UPDATE_COLLECTION_OPERATION:uint = 17;
      
      public static const RELEASE_COLLECTION_OPERATION:uint = 18;
      
      public static const RELEASE_ITEM_OPERATION:uint = 19;
      
      public static const PAGE_ITEMS_OPERATION:uint = 20;
      
      public static const FIND_ITEM_OPERATION:uint = 21;
      
      public static const UPDATE_BODY_CHANGES:uint = 0;
      
      public static const UPDATE_BODY_PREV:uint = 1;
      
      public static const UPDATE_BODY_NEW:uint = 2;
      
      public static const UNKNOWN_OPERATION:uint = 1000;
      
      public static const REMOTE_ALIAS:String = "flex.data.messages.DataMessage";
      
      private static const OPERATIONS:Array = ["create","fill","get","update","delete","batched","multi-batch","transacted","page","count","get or create","create and sequence","get sequence id","synchronize fill","unused14","fill ids","refresh fill","update collection","release collection","release item","page_items"];
       
      
      public var identity:Object;
      
      public var operation:uint;
      
      public function DataMessage()
      {
         super();
         this.operation = DataMessage.UNKNOWN_OPERATION;
      }
      
      public static function wrapItem(item:Object, destination:String) : Object
      {
         var descriptor:SerializationDescriptor = Metadata.getMetadata(destination).serializationDescriptor;
         if(descriptor == null)
         {
            return item;
         }
         return new SerializationProxy(item,descriptor);
      }
      
      public static function unwrapItem(item:Object) : Object
      {
         if(item is SerializationProxy)
         {
            return SerializationProxy(item).instance;
         }
         return item;
      }
      
      public static function getOperationAsString(op:uint) : String
      {
         return op < OPERATIONS.length?OPERATIONS[op]:"unknown";
      }
      
      public function unwrapBody() : Object
      {
         if(body is SerializationProxy)
         {
            return SerializationProxy(body).instance;
         }
         return body;
      }
      
      public function isEmptyUpdate() : Boolean
      {
         return this.operation == DataMessage.UPDATE_OPERATION && (body[DataMessage.UPDATE_BODY_CHANGES] as Array).length == 0;
      }
      
      public function isCreate() : Boolean
      {
         return this.operation == CREATE_OPERATION || this.operation == CREATE_AND_SEQUENCE_OPERATION;
      }
      
      override public function getSmallMessage() : IMessage
      {
         if((this as Object).constructor == DataMessage)
         {
            return new DataMessageExt(this);
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
               if((flags & IDENTITY_FLAG) != 0)
               {
                  this.identity = input.readObject();
               }
               if((flags & OPERATION_FLAG) != 0)
               {
                  this.operation = input.readObject() as uint;
               }
               else
               {
                  this.operation = 0;
               }
               reservedPosition = 2;
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
      
      override public function toString() : String
      {
         var bstr:String = this.operation == UPDATE_OPERATION?"changes: " + Managed.toString(body[UPDATE_BODY_CHANGES]) + "\n, new: " + ConcreteDataService.mx_internal::itemToString(body[UPDATE_BODY_NEW],destination,2) + ", prev: " + ConcreteDataService.mx_internal::itemToString(body[UPDATE_BODY_PREV],destination,2):ConcreteDataService.mx_internal::itemToString(body,destination,2);
         return StringUtil.substitute("(mx.data.messages.DataMessage)\n  messageId = \'{0}\'\n  operation = {1}\n  destination = {2}\n  identity = {3}\n  body = {4}\n  headers = {5}",messageId,DataMessage.getOperationAsString(this.operation),destination,Managed.toString(this.identity,null,null,2),bstr,Managed.toString(headers,null,null,2));
      }
      
      override public function writeExternal(output:IDataOutput) : void
      {
         super.writeExternal(output);
         var flags:uint = 0;
         if(this.identity != null)
         {
            flags = flags | IDENTITY_FLAG;
         }
         if(this.operation != 0)
         {
            flags = flags | OPERATION_FLAG;
         }
         output.writeByte(flags);
         if(this.identity != null)
         {
            output.writeObject(this.identity);
         }
         if(this.operation != 0)
         {
            output.writeObject(this.operation);
         }
      }
   }
}
