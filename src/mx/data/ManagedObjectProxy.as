package mx.data
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.flash_proxy;
   import mx.data.utils.Managed;
   import mx.events.PropertyChangeEvent;
   import mx.utils.ObjectProxy;
   import mx.utils.UIDUtil;
   
   use namespace flash_proxy;
   
   [RemoteClass(alias="flex.messaging.io.ManagedObjectProxy")]
   [Bindable("propertyChange")]
   public dynamic class ManagedObjectProxy extends ObjectProxy implements IManaged
   {
       
      
      var destination:String;
      
      var referencedIds:Object;
      
      private var _uid:String;
      
      public function ManagedObjectProxy(item:Object = null, uid:String = null)
      {
         if(item == null)
         {
            item = new Object();
         }
         super(item,uid,100);
         proxyClass = ManagedObjectProxy;
      }
      
      [Bindable(event="propertyChange")]
      override public function set uid(value:String) : void
      {
         var oldValue:String = this._uid;
         this._uid = value;
         if(this.syncUID)
         {
            object.uid = value;
         }
         if(hasEventListener(PropertyChangeEvent.PROPERTY_CHANGE))
         {
            dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"uid",oldValue,value));
         }
      }
      
      override public function get uid() : String
      {
         if(this._uid == null)
         {
            this._uid = UIDUtil.createUID();
         }
         return this._uid;
      }
      
      override public function readExternal(input:IDataInput) : void
      {
         var key:String = null;
         var value:Object = null;
         var count:int = input.readInt();
         var inst:Object = object;
         for(var i:uint = 0; i < count; i++)
         {
            key = input.readObject() as String;
            value = input.readObject();
            if(key == "type")
            {
               Managed.setProperty(this,key,inst.type,inst.type = value);
            }
            else
            {
               Managed.setProperty(this,key,inst[key],inst[key] = value);
            }
         }
      }
      
      override public function writeExternal(output:IDataOutput) : void
      {
         var propName:* = null;
         var value:Object = null;
         var count:int = 0;
         var obj:Object = object;
         var props:Array = [];
         for(propName in obj)
         {
            value = obj[propName];
            if(!(value is Function))
            {
               if(!Metadata.isLazyAssociation(this,propName))
               {
                  props.push(propName);
               }
            }
         }
         count = 0;
         if(props.length > int.MAX_VALUE)
         {
            count = int.MAX_VALUE;
         }
         else
         {
            count = int(props.length);
         }
         output.writeInt(count);
         for(var i:uint = 0; i < count; i++)
         {
            propName = props[i];
            if(propName == "type")
            {
               value = obj.type;
            }
            else
            {
               value = obj[propName];
            }
            output.writeObject(propName);
            output.writeObject(value);
         }
      }
      
      override flash_proxy function getProperty(name:*) : *
      {
         return object[name] = Managed.getProperty(this,name,object[name]);
      }
      
      override flash_proxy function setProperty(name:*, value:*) : void
      {
         Managed.setProperty(this,name,object[name],object[name] = value);
      }
      
      private function get syncUID() : Boolean
      {
         return "uid" in object && object.uid is String;
      }
   }
}
