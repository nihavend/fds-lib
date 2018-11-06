package mx.data.messages
{
   import flash.utils.IDataOutput;
   import flash.utils.IExternalizable;
   
   [RemoteClass(alias="DSP")]
   public class PagedMessageExt extends PagedMessage implements IExternalizable
   {
       
      
      private var _message:PagedMessage;
      
      public function PagedMessageExt(message:PagedMessage = null)
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
