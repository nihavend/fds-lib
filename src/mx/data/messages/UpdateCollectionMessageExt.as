package mx.data.messages
{
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   
   [RemoteClass(alias="DSU")]
   public class UpdateCollectionMessageExt extends UpdateCollectionMessage implements IExternalizable
   {
       
      
      private var _message:UpdateCollectionMessage;
      
      public function UpdateCollectionMessageExt(message:UpdateCollectionMessage = null)
      {
         super();
         this._message = message;
      }
      
      override public function writeExternal(output:IDataOutput) : void
      {
         if(this._message != null)
         {
            this._message.writeExternal(output);
         }
         else
         {
            super.writeExternal(output);
         }
      }
   }
}
