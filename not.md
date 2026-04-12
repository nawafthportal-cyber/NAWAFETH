لتشغيل السيرفر المحلي:

cd c:\Users\manso\nawafeth\backend
.\.venv\Scripts\python.exe manage.py runserver

لتشغيل محاكي أندرويد محليًا:

emulator -avd Medium_Phone 


cd mobile 

flutter clean
flutter pub get
flutter run -d emulator-5554


ولعرض أسماء المحاكيات المتاحة أولًا:

emulator -list-avds


تحديث قاعدة البيانات 
python manage.py showmigrations
python manage.py migrate


ولو تريد جمع الملفات الثابتة بعد التحديث:
python manage.py collectstatic --noinput

