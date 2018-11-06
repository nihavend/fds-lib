package mx.data
{
   import mx.rpc.AsyncResponder;
   import mx.rpc.AsyncToken;
   
   public class AsyncTokenResponder extends AsyncResponder implements ITokenResponder
   {
       
      
      private var token:AsyncToken;
      
      public function AsyncTokenResponder(result:Function, fault:Function, token:AsyncToken)
      {
         super(result,fault,token);
         token = this.resultToken;
      }
      
      public function get resultToken() : AsyncToken
      {
         return this.token;
      }
   }
}
