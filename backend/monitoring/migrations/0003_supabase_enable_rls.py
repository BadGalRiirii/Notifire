from django.db import migrations


def enable_rls(apps, schema_editor):
    """Supabase exposes the public schema through its Data API (anon key).
    Enabling RLS with no policies blocks that API entirely; Django connects
    as the table owner, which bypasses RLS, so the backend is unaffected."""
    connection = schema_editor.connection
    if connection.vendor != "postgresql":
        return
    with connection.cursor() as cursor:
        cursor.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
        tables = [row[0] for row in cursor.fetchall()]
    for table in tables:
        schema_editor.execute(
            f"ALTER TABLE public.{schema_editor.quote_name(table)} ENABLE ROW LEVEL SECURITY"
        )


class Migration(migrations.Migration):

    dependencies = [
        ("monitoring", "0002_hardware_gas_raw_nullable_dht"),
        ("admin", "0003_logentry_add_action_flag_choices"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
        ("sessions", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(enable_rls, migrations.RunPython.noop),
    ]
