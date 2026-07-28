package io.echelon.governance.skills;

import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

@Service
public class SkillRegistry {

    private final SkillRepository skillRepository;

    public SkillRegistry(SkillRepository skillRepository) {
        this.skillRepository = skillRepository;
    }

    public void register(SkillDefinition skill, String callerRole) {
        skillRepository.save(skill, callerRole);
    }

    public List<SkillDefinition> discover(String category) {
        return skillRepository.findByCategory(category);
    }

    public Optional<SkillDefinition> findByName(String name, String callerRole) {
        return skillRepository.findAll().stream()
            .filter(skill -> skill.name().equals(name))
            .findFirst();
    }

    public List<SkillDefinition> listAll(String callerRole) {
        return skillRepository.findAll();
    }
}
