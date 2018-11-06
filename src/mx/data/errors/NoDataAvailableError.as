package mx.data.errors
{
   import mx.rpc.IResponder;
   
   public class NoDataAvailableError extends Error
   {
       
      
      private var _responder:IResponder;
      
      public function NoDataAvailableError(msg:String = "Requested data not found.")
      {
         super(msg);
      }
      
      public function get responder() : IResponder
      {
         return this._responder;
      }
      
      public function set responder(value:IResponder) : void
      {
         this._responder = value;
      }
   }
}
