package mx.data
{
   import flash.events.EventDispatcher;
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   import mx.core.mx_internal;
   import mx.data.utils.Managed;
   import mx.events.PropertyChangeEvent;
   
   [RemoteClass]
   public class CacheDataDescriptor extends EventDispatcher implements IExternalizable
   {
      
      public static const ALL:uint = 0;
      
      public static const FILL:uint = 1;
      
      public static const ITEM:uint = 2;
      
      private static const VERSION:uint = 1;
       
      
      public var synced:Boolean = false;
      
      var destination:String;
      
      private var _ref:Array;
      
      private var _created:Date;
      
      private var _id:Object;
      
      private var _lastAccessed:Date;
      
      private var _lastWrite:Date;
      
      private var _lastFilled:Date;
      
      private var _metadata:Object;
      
      private var _type:uint;
      
      public function CacheDataDescriptor(dataList:DataList = null)
      {
         super();
         if(dataList != null)
         {
            this._created = new Date();
            this._lastAccessed = new Date();
            this._lastWrite = new Date();
            this._lastFilled = dataList.fillTimestamp;
            mx_internal::references = dataList.mx_internal::localReferences;
            this._id = dataList.mx_internal::collectionId;
            this._type = Boolean(dataList.mx_internal::smo)?uint(CacheDataDescriptor.ITEM):uint(CacheDataDescriptor.FILL);
            this.synced = dataList.mx_internal::sequenceId >= 0;
         }
      }
      
      public function get id() : Object
      {
         return this._id;
      }
      
      public function get created() : Date
      {
         return this._created;
      }
      
      public function get lastAccessed() : Date
      {
         return this._lastAccessed;
      }
      
      public function get lastWrite() : Date
      {
         return this._lastWrite;
      }
      
      public function get lastFilled() : Date
      {
         return this._lastFilled;
      }
      
      public function set lastFilled(value:Date) : void
      {
         this._lastFilled = value;
      }
      
      public function get metadata() : Object
      {
         return this._metadata;
      }
      
      public function set metadata(value:Object) : void
      {
         var oldValue:Object = this._metadata;
         if(value != this._metadata)
         {
            this._metadata = value;
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"metadata",oldValue,value));
         }
      }
      
      public function get type() : uint
      {
         return this._type;
      }
      
      public function readExternal(input:IDataInput) : void
      {
         input.readUnsignedInt();
         this._lastWrite = input.readObject();
         this._lastAccessed = input.readObject();
         this._created = input.readObject();
         this._metadata = input.readObject();
         mx_internal::references = input.readObject();
         this._type = input.readUnsignedInt();
         this._id = input.readObject();
         this.synced = input.readBoolean();
         this._lastFilled = input.readObject();
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         output.writeUnsignedInt(VERSION);
         output.writeObject(this.lastWrite);
         output.writeObject(this.lastAccessed);
         output.writeObject(this.created);
         output.writeObject(this.metadata);
         output.writeObject(mx_internal::references);
         output.writeUnsignedInt(this.type);
         output.writeObject(this.id);
         output.writeBoolean(this.synced);
         output.writeObject(this.lastFilled);
      }
      
      function setTimeAttributes(lastWrite:Date, lastAccessed:Date) : void
      {
         var oldValue:Date = null;
         if(lastAccessed != null && this._lastAccessed.time != lastAccessed.time)
         {
            this._lastAccessed.setTime(lastAccessed.time);
            oldValue = new Date(this._lastAccessed.time);
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"lastAccessed",oldValue,this._lastAccessed));
         }
         if(lastWrite != null && this._lastWrite.time != lastWrite.time)
         {
            oldValue = new Date(this._lastWrite.time);
            this._lastWrite.setTime(lastWrite.time);
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"lastWrite",oldValue,this._lastWrite));
         }
      }
      
      function get references() : Array
      {
         return this._ref;
      }
      
      function set references(value:Array) : void
      {
         this._ref = value;
      }
      
      override public function toString() : String
      {
         return "store id: " + Managed.toString(this.id) + " lastWritten: " + this.lastWrite + " lastAccessed: " + this.lastAccessed + " created: " + this.created + " metadata: " + Managed.toString(this.metadata) + " type: " + this.type + " referenced ids: " + Managed.toString(this._ref);
      }
   }
}
