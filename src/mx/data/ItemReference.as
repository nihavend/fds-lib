package mx.data
{
   import mx.events.PropertyChangeEvent;
   import mx.messaging.messages.IMessage;
   import mx.rpc.AsyncToken;
   
   public dynamic class ItemReference extends AsyncToken implements IITemReference
   {
       
      
      private var _valid:Boolean = false;
      
      var _dataList:DataList;
      
      public function ItemReference(msg:IMessage)
      {
         super(msg);
      }
      
      [Bindable(event="propertyChange")]
      public function get valid() : Boolean
      {
         return this._valid;
      }
      
      public function set valid(value:Boolean) : void
      {
         var event:PropertyChangeEvent = PropertyChangeEvent.createUpdateEvent(this,"valid",this._valid,value);
         this._valid = value;
         dispatchEvent(event);
      }
      
      public function releaseItem(copyStillManagedItems:Boolean = true, enableStillManagedCheck:Boolean = true) : void
      {
         var newRefs:Array = null;
         if(this._dataList != null)
         {
            newRefs = this._dataList.releaseDataList(enableStillManagedCheck,!copyStillManagedItems);
            this.setResult(newRefs[0]);
            this._dataList = null;
         }
      }
      
      override function setResult(value:Object) : void
      {
         super.setResult(value);
         this.valid = true;
      }
   }
}
