package mx.data
{
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.events.IEventDispatcher;
   import flash.utils.Proxy;
   import flash.utils.flash_proxy;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import mx.data.utils.Managed;
   import mx.events.PropertyChangeEvent;
   import mx.utils.UIDUtil;
   
   [Managed]
   public dynamic class DynamicManagedItem extends Proxy implements IManaged
   {
       
      
      private var propertyValues:Object;
      
      [Transient]
      private var propertyNames:Array;
      
      private var _115792uid:String;
      
      var referencedIds:Object;
      
      var destination:String;
      
      private var _eventDispatcher:EventDispatcher;
      
      public function DynamicManagedItem()
      {
         this.propertyValues = {};
         this.referencedIds = {};
         this._eventDispatcher = new EventDispatcher(IEventDispatcher(this));
         super();
      }
      
      private function ensureNamesPresent() : void
      {
         var name:* = undefined;
         if(!this.propertyNames)
         {
            this.propertyNames = [];
            for(name in this.propertyValues)
            {
               this.propertyNames.push(name);
            }
         }
      }
      
      override flash_proxy function nextNameIndex(index:int) : int
      {
         this.ensureNamesPresent();
         if(0 <= index && index < this.propertyNames.length)
         {
            return index + 1;
         }
         return 0;
      }
      
      override flash_proxy function nextName(index:int) : String
      {
         this.ensureNamesPresent();
         return this.propertyNames[index - 1];
      }
      
      override flash_proxy function nextValue(index:int) : *
      {
         return this.getProperty(this.nextName(index));
      }
      
      override flash_proxy function getProperty(name:*) : *
      {
         var className:String = null;
         var nameAsString:String = name.toString();
         if(nameAsString == "constructor")
         {
            className = getQualifiedClassName(this);
            return getDefinitionByName(className) as Class;
         }
         var value:* = this.propertyValues[name];
         var returnedValue:* = Managed.getProperty(this,name,value);
         if(value !== returnedValue)
         {
            this.propertyValues[name] = returnedValue;
         }
         return returnedValue;
      }
      
      override flash_proxy function setProperty(name:*, value:*) : void
      {
         var oldValue:* = undefined;
         if(value === undefined)
         {
            this.deleteProperty(name);
         }
         else
         {
            oldValue = this.propertyValues[name];
            this.propertyValues[name] = value;
            this.propertyNames = null;
            Managed.setProperty(this,name,oldValue,value);
         }
      }
      
      override flash_proxy function deleteProperty(name:*) : Boolean
      {
         var oldValue:* = undefined;
         var result:Boolean = true;
         if(this.propertyValues.hasOwnProperty(name))
         {
            oldValue = this.propertyValues[name];
            result = delete this.propertyValues[name];
            this.propertyNames = null;
            Managed.setProperty(this,name,oldValue,undefined);
         }
         return result;
      }
      
      override flash_proxy function hasProperty(name:*) : Boolean
      {
         return this.propertyValues.hasOwnProperty(name);
      }
      
      override flash_proxy function callProperty(name:*, ... parameters) : *
      {
         var f:Function = this.getProperty(name);
         if(f == null)
         {
            return super.callProperty(name,parameters);
         }
         return f.apply(this,parameters);
      }
      
      [Bindable(event="propertyChange")]
      [Transient]
      public function get uid() : String
      {
         if(this._115792uid == null)
         {
            this._115792uid = UIDUtil.createUID();
         }
         return this._115792uid;
      }
      
      public function set uid(value:String) : void
      {
         var oldValue:String = this._115792uid;
         if(oldValue !== value)
         {
            this._115792uid = value;
            this.dispatchEvent(PropertyChangeEvent.createUpdateEvent(this,"uid",oldValue,value));
         }
      }
      
      public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, weakRef:Boolean = false) : void
      {
         this._eventDispatcher.addEventListener(type,listener,useCapture,priority,weakRef);
      }
      
      public function dispatchEvent(event:Event) : Boolean
      {
         return this._eventDispatcher.dispatchEvent(event);
      }
      
      public function hasEventListener(type:String) : Boolean
      {
         return this._eventDispatcher.hasEventListener(type);
      }
      
      public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false) : void
      {
         this._eventDispatcher.removeEventListener(type,listener,useCapture);
      }
      
      public function willTrigger(type:String) : Boolean
      {
         return this._eventDispatcher.willTrigger(type);
      }
   }
}
