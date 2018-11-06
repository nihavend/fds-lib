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
   
   [RemoteClass(alias="flex.data.messages.ManagedRemoteServiceMessage")]
   public class ManagedRemoteServiceMessage extends AsyncMessage
   {
      
      private static const IDENTITY_FLAG:uint = 1;
      
      private static const OPERATION_FLAG:uint = 2;
      
      private static const OPERATION_METHOD_NAME_FLAG:uint = 3;
      
      public static const CREATE_OPERATION:uint = DataMessage.CREATE_OPERATION;
      
      public static const FILL_OPERATION:uint = DataMessage.FILL_OPERATION;
      
      public static const GET_OPERATION:uint = DataMessage.GET_OPERATION;
      
      public static const UPDATE_OPERATION:uint = DataMessage.UPDATE_OPERATION;
      
      public static const DELETE_OPERATION:uint = DataMessage.DELETE_OPERATION;
      
      public static const FIND_ITEM_OPERATION:uint = DataMessage.FIND_ITEM_OPERATION;
      
      public static const INCLUDE_OPERATION:uint = 100;
      
      public static const UPDATE_BODY_CHANGES:uint = DataMessage.UPDATE_BODY_CHANGES;
      
      public static const UPDATE_BODY_PREV:uint = DataMessage.UPDATE_BODY_PREV;
      
      public static const UPDATE_BODY_NEW:uint = DataMessage.UPDATE_BODY_NEW;
      
      public static const UNKNOWN_OPERATION:uint = DataMessage.UNKNOWN_OPERATION;
      
      public static const REMOTE_ALIAS:String = "flex.data.messages.ManagedRemoteServiceMessage";
      
      private static const OPERATIONS:Array = ["create","fill","get","update","delete","page","find-item","count","fill ids","refresh fill","update collection","release collection","release item","page_items","include"];
       
      
      public var identity:Object;
      
      public var operation:uint;
      
      public var operationMethodName:String;
      
      public var name:String;
      
      public var source:String;
      
      public function ManagedRemoteServiceMessage()
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
         return this.operation == CREATE_OPERATION;
      }
      
      override public function getSmallMessage() : IMessage
      {
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
         return StringUtil.substitute("(mx.data.messages.ManagedRemoteMessage)\n  messageId = \'{0}\'\n  operation = {1}\n  destination = {2}\n  identity = {3}\n  body = {4}\n  headers = {5}",messageId,DataMessage.getOperationAsString(this.operation),destination,Managed.toString(this.identity,null,null,2),bstr,Managed.toString(headers,null,null,2));
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
         if(this.operationMethodName != null)
         {
            output.writeObject(this.operationMethodName);
         }
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
