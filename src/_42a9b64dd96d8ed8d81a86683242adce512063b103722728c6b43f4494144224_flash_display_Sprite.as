package
{
   import flash.display.Sprite;
   import flash.system.Security;
   
   [ExcludeClass]
   public class _42a9b64dd96d8ed8d81a86683242adce512063b103722728c6b43f4494144224_flash_display_Sprite extends Sprite
   {
       
      
      public function _42a9b64dd96d8ed8d81a86683242adce512063b103722728c6b43f4494144224_flash_display_Sprite()
      {
         super();
      }
      
      public function allowDomainInRSL(... rest) : void
      {
         Security.allowDomain(rest);
      }
      
      public function allowInsecureDomainInRSL(... rest) : void
      {
         Security.allowInsecureDomain(rest);
      }
   }
}
