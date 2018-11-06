package mx.data
{
   import flash.utils.IDataInput;
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   
   [RemoteClass(alias="flex.data.ChangedItems")]
   public class ChangedItems implements IExternalizable
   {
       
      
      public var sinceTimestamp:Date;
      
      public var createdItems:Array;
      
      public var updatedItems:Array;
      
      public var deletedItemIds:Array;
      
      public var fillParameters:Array;
      
      public var resultTimestamp:Date;
      
      public function ChangedItems()
      {
         this.createdItems = [];
         this.updatedItems = [];
         this.deletedItemIds = [];
         super();
      }
      
      public function readExternal(input:IDataInput) : void
      {
         this.sinceTimestamp = input.readObject();
         this.resultTimestamp = input.readObject();
         this.fillParameters = input.readObject();
         this.deletedItemIds = input.readObject();
         this.createdItems = input.readObject();
         this.updatedItems = input.readObject();
      }
      
      public function writeExternal(output:IDataOutput) : void
      {
         output.writeObject(this.sinceTimestamp);
         output.writeObject(this.resultTimestamp);
         output.writeObject(this.fillParameters);
         output.writeObject(this.deletedItemIds);
         output.writeObject(this.createdItems);
         output.writeObject(this.updatedItems);
      }
   }
}
