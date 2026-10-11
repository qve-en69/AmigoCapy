using System.Windows;

namespace AmigoClick
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            Theme.Apply(Resources);
            base.OnStartup(e);
        }
    }
}
