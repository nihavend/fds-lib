package mx.data
{
   import mx.rpc.AsyncToken;
   import mx.rpc.IResponder;
   
   public interface ITokenResponder extends IResponder
   {
       
      
      function get resultToken() : AsyncToken;
   }
}
