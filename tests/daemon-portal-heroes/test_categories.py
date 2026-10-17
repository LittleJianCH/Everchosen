"""Native recruitment-category rows also need the shared category labels."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'portal_heroes', ROOT / 'mods/daemon-portal-heroes/generator/generate.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
from db_tables import Table


class CategoryLabels(unittest.TestCase):
    def test_existing_and_added_records_get_names_and_descriptions(self):
        native = {'agent_culture_details': Table('agent_culture_details', [], '9', [
            {'key': 'native-spy', 'agent': 'spy', 'culture': module.CULTURE},
            {'key': 'native-cultist', 'agent': 'dignitary', 'culture': module.CULTURE},
            {'key': 'native-wizard', 'agent': 'wizard', 'culture': module.CULTURE},
            {'key': 'other-culture', 'agent': 'spy', 'culture': 'wh3_main_nur_nurgle'},
        ])}
        generated = {'agent_culture_details': [
            {'key': 'added-priest', 'agent': 'runesmith', 'culture': module.CULTURE}]}
        result = {r['key']: r['text']
                  for r in module.category_localisation(native, generated)}
        self.assertEqual(len(result), 6)
        for key, name in [('native-spy', '瘟疫使徒'),
                          ('native-cultist', '混沌使徒'),
                          ('added-priest', '混沌祭司')]:
            self.assertEqual(result['agent_culture_details_onscreen_name_' + key], name)
            self.assertTrue(result['agent_culture_details_description_text_' + key])


if __name__ == '__main__':
    unittest.main()
