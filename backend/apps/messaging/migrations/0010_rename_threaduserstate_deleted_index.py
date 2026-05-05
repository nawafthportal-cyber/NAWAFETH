from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ("messaging", "0009_threaduserstate_soft_delete"),
    ]

    operations = [
        migrations.RenameIndex(
            model_name="threaduserstate",
            new_name="messaging_t_user_del_idx",
            old_name="messaging_t_user_id_deleted_idx",
        ),
    ]